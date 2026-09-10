"""MultiSourceCollectionService — orquestrador multi-fonte (PR 6, D8=A).

Este servico e o **Strangler Fig** sobre o :class:`CollectionService`
legado: cresce AO REDOR do pipeline historico (que permanece intacto e
continua sendo o caminho de producao do ENERGY STAR) consumindo apenas
os protocols DIP (:class:`SourceAdapter`), sem nenhuma dependencia de
classe concreta (SocrataClient, WattSimpleClient, ...).

Roteamento por ``adapter.source_type`` (a decisao de tabela e da FONTE,
nao do chamador):

* ``"individual_product"`` → :func:`upsert_batch` (tabela ``product``) +
  :func:`upsert_label_classes` (ENCE, quando a fonte declara — ex.
  INMETRO).
* ``"aggregate"`` → :func:`upsert_aggregates` (tabela
  ``aggregate_reference``) — dados anonimos (IEA), nunca ``product``.

Diferencas deliberadas em relacao ao legado:

* **Sem estado de retomada**: as fontes atuais do multi-source sao
  snapshots estaticos (CSV injetavel), nao APIs paginadas longas — a
  maquina de resume do legado e desnecessaria aqui. Quando uma fonte
  paginada real entrar, o protocolo ``iter_raw_records`` ja devolve o
  offset necessario para retomada futura.
* **Sequencial por dataset**: coletas de snapshot sao rapidas e o
  gargalo e o banco; o paralelismo do legado (8x4) existe por causa do
  volume Socrata. Reusar as estruturas de relatorio mantem a paridade
  de observabilidade.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from ..database import (
    upsert_aggregates,
    upsert_batch,
    upsert_label_classes,
    upsert_source_observations,
)
from ..exceptions import PersistenceError
from ..models import AggregateRecord, NormalizedProduct, Product, merge_products
from ..pagination import DEFAULT_PAGE_SIZE
from .collection import CategoryReport, CollectionReport

if TYPE_CHECKING:
    from psycopg_pool import ConnectionPool

    from ..sources.protocol import RawRecord, SourceAdapter

logger = logging.getLogger(__name__)


class MultiSourceCollectionService:
    """Orquestra qualquer :class:`SourceAdapter` ate o PostgreSQL.

    Contrato simples: um metodo publico :meth:`collect` por dataset;
    o chamador (CLI ou teste) monta o par ``(adapter, dataset_id)`` e
    consome um :class:`CategoryReport` no mesmo formato do legado.
    """

    def __init__(
        self,
        pool: ConnectionPool,
        page_size: int = DEFAULT_PAGE_SIZE,
    ) -> None:
        self.pool = pool
        self.page_size = page_size

    # ------------------------------------------------------------------ #
    # API publica
    # ------------------------------------------------------------------ #
    def collect(
        self,
        adapter: SourceAdapter,
        *,
        dataset_id: str,
        category: str,
        limit: int | None = None,
    ) -> CategoryReport:
        """Varre um dataset de uma fonte e persiste conforme o tipo.

        Args:
            adapter: Adapter DIP da fonte (ENERGY STAR, WattSimple,
                INMETRO, IEA, ...).
            dataset_id: Identificador do dataset NA fonte.
            category: Rotulo logico para o relatorio.
            limit: Teto opcional de registros (smoke tests).

        Returns:
            ``CategoryReport`` (mesmo contrato do legado, FR-011).
        """
        rep = CategoryReport(category=category, dataset_id=dataset_id)
        all_products: list[Product] = []
        try:
            for offset, records in adapter.iter_raw_records(
                dataset_id=dataset_id,
                page_size=self.page_size,
                limit=limit,
            ):
                rep.received += len(records)
                products, aggregates, discarded = self._normalize_page(
                    adapter, records, dataset_id, category
                )
                rep.discarded += discarded
                all_products.extend(products)
                self._persist_page(
                    adapter, dataset_id, offset, products, aggregates, rep
                )
            # A source may span many pages. The canonical average must use
            # every observation in the dataset, not only the current page.
            if all_products:
                self._persist_products(dataset_id, 0, all_products, rep)
        except PersistenceError as exc:
            logger.error("[%s] %s — persistencia falhou: %s", dataset_id, category, exc)
            rep.status = "failed"
        except Exception:
            logger.exception("[%s] %s — erro inesperado", dataset_id, category)
            rep.status = "failed"
            return rep

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

    def collect_all(
        self, adapter: SourceAdapter, *, limit: int | None = None
    ) -> CollectionReport:
        """Varre TODOS os datasets descobertos pela fonte.

        Uses ``adapter``'s client ``discover()`` via iteracao — como o
        protocolo nao expoe o client, espera-se que subclasses de
        adapter publiquem seus datasets; fontes de dataset unico podem
        simplesmente redeclarar :meth:`collect`. Este metodo cobre os
        adapters que expoe ``discover_datasets`` (opcional).
        """
        report = CollectionReport()
        discover = getattr(adapter, "discover_datasets", None)
        if not callable(discover):
            raise TypeError(
                f"Adapter {type(adapter).__name__} nao expoe "
                "'discover_datasets'; use collect() com dataset_id explicito."
            )
        for dataset_id, category in discover():
            report.per_category.append(
                self.collect(
                    adapter, dataset_id=dataset_id, category=category, limit=limit
                )
            )
        return report

    # ------------------------------------------------------------------ #
    # Normalizacao (puro — unit-testavel, sem I/O)
    # ------------------------------------------------------------------ #
    def _normalize_page(
        self,
        adapter: SourceAdapter,
        records: list[RawRecord],
        dataset_id: str,
        category: str,
    ) -> tuple[list[Product], list[AggregateRecord], int]:
        """Normaliza uma pagina; separa produtos, agregados e descartes.

        O roteamento por tipo e DEFENSIVO (isinstance): uma fonte nunca
        deve misturar tipos, mas o servico sobrevive a adapters futuros
        que o facam.
        """
        products: list[Product] = []
        aggregates: list[AggregateRecord] = []
        discarded = 0

        for raw_record in records:
            result = adapter.normalize(
                raw_record, dataset_id=dataset_id, category=category
            )
            if result is None:
                discarded += 1
                continue
            if isinstance(result, AggregateRecord):
                aggregates.append(result)
                continue
            if isinstance(result, NormalizedProduct):
                # ENERGY STAR exposes the richer normalization contract so
                # raw/derived values remain available to future persistence
                # adapters. The current product table still receives only
                # the canonical Product projection.
                result = result.product
            if isinstance(result, Product):
                ok, reason = result.validate()
                if not ok:
                    discarded += 1
                    logger.debug("Descartado em %s: %s", dataset_id, reason)
                    continue
                products.append(result)
                continue
            # Tipo desconhecido: descarta ruidosamente (contrato violado).
            discarded += 1
            logger.warning(
                "[%s] normalize() retornou tipo inesperado %r — descartado",
                dataset_id,
                type(result).__name__,
            )

        return products, aggregates, discarded

    # ------------------------------------------------------------------ #
    # Persistencia (rota por source_type)
    # ------------------------------------------------------------------ #
    def _persist_page(
        self,
        adapter: SourceAdapter,
        dataset_id: str,
        offset: int,
        products: list[Product],
        aggregates: list[AggregateRecord],
        rep: CategoryReport,
    ) -> None:
        """Roteia a persistencia por TIPO DE DADO separado no normalize.

        O ``source_type`` e o contrato primario, mas o roteamento e
        defensivo: qualquer agregado que venha de fonte individual (ou
        vice-versa) persiste na tabela CORRETA — o dado manda, nao a
        declaracao da fonte. Assim um bug de adapter nunca escreve um
        agregado na tabela ``product``.
        """
        if adapter.source_type == "aggregate":
            self._persist_aggregates(dataset_id, offset, aggregates, rep)
        # Defensivo: agregados vindos de fonte individual (MixedAdapter
        # scenario) NAO sao descartados silenciosamente.
        if adapter.source_type != "aggregate" and aggregates:
            self._persist_aggregates(dataset_id, offset, aggregates, rep)

    def _persist_products(
        self, dataset_id: str, offset: int, products: list[Product], rep: CategoryReport
    ) -> None:
        if not products:
            return
        canonical_products = merge_products(products)
        stats = upsert_batch(self.pool, canonical_products)
        rep.inserted += stats.inserted
        rep.updated += stats.updated
        upsert_source_observations(self.pool, products)
        # ENCE é projetada no produto canônico para manter o contrato Spring.
        upsert_label_classes(self.pool, canonical_products)

    def _persist_aggregates(
        self,
        dataset_id: str,
        offset: int,
        aggregates: list[AggregateRecord],
        rep: CategoryReport,
    ) -> None:
        if not aggregates:
            return
        written = upsert_aggregates(self.pool, aggregates)
        rep.inserted += written


__all__ = ["MultiSourceCollectionService"]
