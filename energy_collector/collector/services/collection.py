"""CollectionService — orquestracao do pipeline de coleta.

Pipeline por dataset: fetch (paginacao estavel) → normalize → validate →
persist (upsert em lote idempotente). Cobre as tres user stories da spec:

* US-1 (P1): varrer TODOS os datasets elegiveis sem intervencao manual e
  povoar ``product``.
* US-2 (P2): reexecucao idempotente — 0 duplicadas, apenas updates/no-ops,
  via identidade uuid5 + ON CONFLICT.
* US-3 (P3): retomada apos interrupcao com estado atomico; lote ou dataset
  que falha e isolado e as demais seguem.

Modos de execucao:

* ``run_sequential`` — baseline/debug (um client, um escritor).
* ``run_concurrent`` — N threads produtoras (cada uma com seu proprio
  SocrataClient/Session; rate limiter compartilhado vem de fora) +
  fila com backpressure + M threads escritoras sobre o pool (FR-007).
  Lotes ordenados por UUID evitam deadlock; transacoes curtas isolam
  falhas por lote.
"""

from __future__ import annotations

import logging
import queue
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any, Callable

from ..api_client import SocrataClient, SocrataError
from ..config import KNOWN_DATASETS, STATE_FILE
from ..database import UpsertStats, upsert_batch
from ..normalization import normalize, slugify_category
from ..pagination import (
    DEFAULT_PAGE_SIZE,
    DONE,
    clear_state,
    iter_pages,
    load_state,
    resume_offset,
    save_state,
)

if TYPE_CHECKING:
    from psycopg_pool import ConnectionPool

    from ..models import Product

logger = logging.getLogger(__name__)

#: Marcador interno de fim de dataset na fila (offset -1).
_DONE_OFFSET = -1


@dataclass(slots=True)
class CategoryReport:
    """Totais de uma categoria/dataset para o relatorio final (FR-011)."""

    category: str
    dataset_id: str = ""
    received: int = 0
    inserted: int = 0
    updated: int = 0
    discarded: int = 0
    status: str = "ok"  # ok | failed | skipped(done)


@dataclass(slots=True)
class CollectionReport:
    """Relatorio final da varredura: totais por categoria + agregado."""

    per_category: list[CategoryReport] = field(default_factory=list)

    @property
    def totals(self) -> CategoryReport:
        """Agrega os totais de todas as categorias."""
        total = CategoryReport(category="TOTAL")
        for cat in self.per_category:
            total.received += cat.received
            total.inserted += cat.inserted
            total.updated += cat.updated
            total.discarded += cat.discarded
            if cat.status == "failed":
                total.status = "partial"
        return total


class CollectionService:
    """Servico de coleta: orquestra client, normalizacao, banco e estado."""

    def __init__(
        self,
        make_client: Callable[[], SocrataClient],
        pool: "ConnectionPool",
        datasets: dict[str, str] | None = None,
        state_path: str | Path = STATE_FILE,
        page_size: int = DEFAULT_PAGE_SIZE,
    ) -> None:
        """
        Args:
            make_client: factory que cria um SocrataClient NOVO (um por
                thread produtora — Session nao e thread-safe).
            pool: pool de conexoes do banco (escritoras).
            datasets: mapeamento explicito ``{4x4: categoria}``; quando
                None, a varredura descobre o catalogo inteiro (FR-001).
            state_path: arquivo de estado para retomada.
            page_size: tamanho da pagina/lote de fetch.
        """
        self._make_client = make_client
        self.pool = pool
        self.datasets = datasets
        self.state_path = Path(state_path)
        self.page_size = page_size

    # ------------------------------------------------------------------ #
    # Alvos
    # ------------------------------------------------------------------ #
    def resolve_targets(self, client: SocrataClient) -> list[tuple[str, str]]:
        """Retorna ``[(dataset_id, categoria)]`` ordenado por categoria."""
        if self.datasets:
            return sorted(self.datasets.items(), key=lambda item: item[1])
        targets: list[tuple[str, str]] = []
        for dataset_id, name in client.discover():
            known = KNOWN_DATASETS.get(dataset_id)
            known_category = known.get("category") if known else None
            category = known_category if known_category else slugify_category(name)
            targets.append((dataset_id, category))
        return targets

    # ------------------------------------------------------------------ #
    # Pipeline compartilhado (puro — sem I/O de rede, unit-testavel)
    # ------------------------------------------------------------------ #
    def _process_page(
        self, dataset_id: str, category: str, records: list[dict[str, Any]]
    ) -> tuple[list["Product"], int]:
        """Normaliza + valida uma pagina; retorna (produtos, descartados)."""
        products: list[Product] = []
        discarded = 0
        for raw in records:
            product = normalize(raw, dataset_id, category)
            if product is None:
                discarded += 1
                continue
            ok, reason = product.validate()
            if not ok:
                discarded += 1
                logger.debug("Descartado em %s: %s", dataset_id, reason)
                continue
            products.append(product)
        return products, discarded

    # ------------------------------------------------------------------ #
    # Modo sequencial (baseline / debug)
    # ------------------------------------------------------------------ #
    def run_sequential(
        self, resume: bool = False, limit: int | None = None
    ) -> CollectionReport:
        """Varredura sequencial: um client, escrita no mesmo thread."""
        report = CollectionReport()
        stateful = resume and limit is None
        state = load_state(self.state_path) if stateful else {}

        with self._make_client() as client:
            targets = self.resolve_targets(client)
            logger.info("Varredura sequencial: %d datasets", len(targets))
            for dataset_id, category in targets:
                rep = self._collect_dataset_seq(
                    client, dataset_id, category, state, stateful, limit
                )
                report.per_category.append(rep)

        self._finish_state(stateful, state, report)
        return report

    def _collect_dataset_seq(
        self,
        client: SocrataClient,
        dataset_id: str,
        category: str,
        state: dict[str, Any],
        stateful: bool,
        limit: int | None,
    ) -> CategoryReport:
        rep = CategoryReport(category=category, dataset_id=dataset_id)

        start = 0
        if stateful:
            offset = resume_offset(state, dataset_id)
            if offset is None:
                rep.status = "skipped(done)"
                logger.info("[%s] %s — ja concluido, pulando", dataset_id, category)
                return rep
            start = offset

        total: int | None = None
        try:
            total = client.count(dataset_id)
        except SocrataError as exc:
            logger.warning("count(%s) falhou (%s); seguindo sem total", dataset_id, exc)

        try:
            for offset, page in iter_pages(
                client,
                dataset_id,
                page_size=self.page_size,
                start_offset=start,
                total=total,
                limit=limit,
            ):
                rep.received += len(page)
                products, discarded = self._process_page(dataset_id, category, page)
                rep.discarded += discarded
                self._persist(dataset_id, offset, products, rep)
                if stateful:
                    state[dataset_id] = offset + len(page)
                    save_state(self.state_path, state)
        except SocrataError as exc:
            logger.error("[%s] %s — fetch falhou: %s", dataset_id, category, exc)
            rep.status = "failed"
            return rep

        if stateful:
            state[dataset_id] = DONE
            save_state(self.state_path, state)
        logger.info(
            "[%s] %s — recebidos=%d inseridos=%d atualizados=%d descartados=%d",
            dataset_id,
            category,
            rep.received,
            rep.inserted,
            rep.updated,
            rep.discarded,
        )
        return rep

    # ------------------------------------------------------------------ #
    # Modo concorrente (produtores -> fila -> escritoras)
    # ------------------------------------------------------------------ #
    def run_concurrent(
        self,
        fetch_workers: int = 8,
        db_workers: int = 4,
        resume: bool = False,
        limit: int | None = None,
    ) -> CollectionReport:
        """Varredura com paralelismo real (FR-007).

        Produtores: uma thread por dataset (pool de ``fetch_workers``),
        cada uma com SocrataClient proprio. Escritoras: ``db_workers``
        threads fixas consumindo paginas da fila e gravando lotes curtos
        via pool. Backpressure pela fila limitada.
        """
        stateful = resume and limit is None
        state: dict[str, Any] = load_state(self.state_path) if stateful else {}
        state_lock = threading.Lock()
        stats_lock = threading.Lock()
        work_q: queue.Queue[tuple[str, str, int, list[dict[str, Any]] | None]] = (
            queue.Queue(maxsize=32)
        )

        with self._make_client() as client:
            targets = self.resolve_targets(client)

        reports: dict[str, CategoryReport] = {}
        active: list[tuple[str, str]] = []
        for dataset_id, category in targets:
            rep = CategoryReport(category=category, dataset_id=dataset_id)
            reports[category] = rep
            if stateful and resume_offset(state, dataset_id) is None:
                rep.status = "skipped(done)"
                continue
            active.append((dataset_id, category))

        logger.info(
            "Varredura concorrente: %d datasets ativos (%d produtores, %d escritoras)",
            len(active),
            fetch_workers,
            db_workers,
        )

        def producer(dataset_id: str, category: str) -> None:
            rep = reports[category]
            client = self._make_client()
            try:
                start = 0
                if stateful:
                    offset = resume_offset(state, dataset_id)
                    start = offset or 0
                total: int | None = None
                try:
                    total = client.count(dataset_id)
                except SocrataError as exc:
                    logger.warning("count(%s) falhou (%s)", dataset_id, exc)
                for offset, page in iter_pages(
                    client,
                    dataset_id,
                    page_size=self.page_size,
                    start_offset=start,
                    total=total,
                    limit=limit,
                ):
                    work_q.put((dataset_id, category, offset, page))
            except SocrataError as exc:
                logger.error("[%s] %s — fetch falhou: %s", dataset_id, category, exc)
                rep.status = "failed"
            except Exception as exc:  # noqa: BLE001 - isola o dataset
                logger.exception(
                    "[%s] %s — erro inesperado: %s", dataset_id, category, exc
                )
                rep.status = "failed"
            finally:
                client.close()
                work_q.put((dataset_id, category, _DONE_OFFSET, None))

        def writer() -> None:
            while True:
                item = work_q.get()
                if item is None:
                    break
                dataset_id, category, offset, page = item
                try:
                    if offset == _DONE_OFFSET:
                        if stateful:
                            with state_lock:
                                state[dataset_id] = DONE
                                save_state(self.state_path, state)
                        continue
                    rep = reports[category]
                    assert page is not None
                    try:
                        products, discarded = self._process_page(
                            dataset_id, category, page
                        )
                    except Exception:  # noqa: BLE001 - isola a pagina
                        logger.exception(
                            "[%s] normalizacao falhou (offset=%d); pagina isolada",
                            dataset_id,
                            offset,
                        )
                        continue
                    self._persist(dataset_id, offset, products, rep, stats_lock)
                    with stats_lock:
                        rep.received += len(page)
                        rep.discarded += discarded
                    if stateful:
                        with state_lock:
                            state[dataset_id] = offset + len(page)
                            save_state(self.state_path, state)
                finally:
                    work_q.task_done()

        writers = [
            threading.Thread(target=writer, name=f"db-writer-{i}", daemon=True)
            for i in range(db_workers)
        ]
        for thread in writers:
            thread.start()

        with ThreadPoolExecutor(max_workers=fetch_workers) as executor:
            futures = [
                executor.submit(producer, dataset_id, category)
                for dataset_id, category in active
            ]
            for future in futures:
                future.result()  # excecoes ja isoladas dentro do producer

        for _ in writers:
            work_q.put(None)  # type: ignore[arg-type]  # sentinela de fim
        for thread in writers:
            thread.join()

        report = CollectionReport(
            per_category=sorted(reports.values(), key=lambda r: r.category)
        )
        self._finish_state(stateful, state, report)
        return report

    # ------------------------------------------------------------------ #
    # Persistencia isolada por lote (US-3, cenario 2)
    # ------------------------------------------------------------------ #
    def _persist(
        self,
        dataset_id: str,
        offset: int,
        products: list["Product"],
        rep: CategoryReport,
        stats_lock: threading.Lock | None = None,
    ) -> None:
        try:
            stats: UpsertStats = upsert_batch(self.pool, products)
        except Exception as exc:  # noqa: BLE001 - lote isolado, varredura segue
            logger.error(
                "[%s] falha ao gravar lote offset=%d (%s) — lote descartado",
                dataset_id,
                offset,
                exc,
            )
            return

        def _accumulate() -> None:
            rep.inserted += stats.inserted
            rep.updated += stats.updated

        if stats_lock is None:
            _accumulate()
        else:
            with stats_lock:
                _accumulate()

    def _finish_state(
        self,
        stateful: bool,
        state: dict[str, Any],
        report: CollectionReport,
    ) -> None:
        """Limpa o estado quando TODA a varredura terminou sem falhas."""
        if not stateful or not state:
            return
        if any(rep.status == "failed" for rep in report.per_category):
            logger.warning("Varredura com falhas — estado mantido para --resume")
            return
        if all(value == DONE for value in state.values()):
            clear_state(self.state_path)
            logger.info("Varredura concluida — estado de retomada limpo")
