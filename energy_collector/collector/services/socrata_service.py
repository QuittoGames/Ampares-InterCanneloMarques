"""SocrataService — camada de integracao com a API Socrata do ENERGY STAR.

Responsabilidade EXCLUSIVA: trazer os dados BRUTOS da API para o nivel do
software. Este servico NAO decide categoria, perfil de uso, horas de
utilizacao, estimativas artificiais ou classificacao — ele e uma camada de
integracao, nao uma camada de inteligencia.

Ele abstrai (para quem esta acima):

* URL base da API (``SOCRATA_BASE``);
* dataset ID;
* paginacao (``$limit``/``$offset`` com ``$order=:id`` estavel);
* limites e offsets;
* filtros e selecao de campos;
* tratamento de erros HTTP e retries;
* parsing da resposta JSON;
* metadados da consulta (``QueryMetadata``).

O codigo acima do servico pode fazer algo conceitualmente como::

    records = socrata_service.fetch(dataset_id)

sem montar manualmente URLs ou lidar com paginacao/erros.

Contrato com o normalizer::

    raw_records = socrata_service.fetch(dataset_id)
    for raw in raw_records:
        record = normalizer.normalize_record(raw=raw, dataset_id=dataset_id)

O servico conhece Socrata/HTTP/paginacao/datasets/queries.
O normalizer conhece tipos/campos/energia/valores/conversoes/derivados.
Nenhum dos dois assume responsabilidades da camada de dominio.

Reutiliza :class:`collector.api_client.SocrataClient` (que ja encapsula
retry, rate limit, parsing e erros HTTP) — este servico NAO duplica essa
logica: apenas apresenta uma API mais alta e orientada a "dataset".
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

from ..api_client import SocrataClient, SocrataError
from ..pagination import DEFAULT_PAGE_SIZE

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class QueryMetadata:
    """Metadados de uma consulta (rastreabilidade, nao dados de dominio).

    Permite ao chamador saber de qual dataset/intervalo vieram os
    registros, quantos ha no total e se a consulta foi limitada.
    """

    dataset_id: str
    offset: int
    limit: int
    total: int | None = None
    truncated: bool = False


class SocrataService:
    """Integracao com a API Socrata, orientada a dataset.

    Nao compartilhe uma instancia entre threads (ela delega para um
    :class:`SocrataClient`, cuja ``requests.Session`` nao e thread-safe).
    No modo concorrente, crie UMA instancia por thread produtora,
    compartilhando apenas o ``RateLimiter``.
    """

    def __init__(
        self,
        client: SocrataClient,
        page_size: int = DEFAULT_PAGE_SIZE,
    ) -> None:
        """
        Args:
            client: Cliente Socrata pronto (uma instancia por thread).
            page_size: Tamanho de pagina padrao para :meth:`fetch`.
        """
        self._client = client
        self.page_size = page_size

    # ------------------------------------------------------------------ #
    # Fonte de config / metadados
    # ------------------------------------------------------------------ #
    @property
    def base_url(self) -> str:
        """Base da API Socrata (so leitura, exposto para logs/diagnostico)."""
        return self._client.base_url

    # ------------------------------------------------------------------ #
    # Pagina unica
    # ------------------------------------------------------------------ #
    def fetch_page(
        self,
        dataset_id: str,
        limit: int | None = None,
        offset: int = 0,
        *,
        order: str = ":id",
    ) -> tuple[list[dict[str, Any]], QueryMetadata]:
        """Busca UMA pagina de registros crus.

        Args:
            dataset_id: ID 4x4 do dataset.
            limit: Limite de registros (padrao ``self.page_size``).
            offset: Deslocamento inicial.
            order: Campo de ordenacao (``$order``). Padrao ``:id`` (estavel).

        Returns:
            Tupla ``(records, metadados)`` — ``records`` e a lista de dicts
            BRUTOS, sem nenhuma normalizacao/classificacao.

        Raises:
            SocrataError: falha irrecuperavel de HTTP/parse apos retries.
        """
        page_limit = limit if limit is not None else self.page_size
        records = self._client.fetch_page(dataset_id, limit=page_limit, offset=offset)
        meta = QueryMetadata(
            dataset_id=dataset_id,
            offset=offset,
            limit=page_limit,
            truncated=len(records) == page_limit,
        )
        return records, meta

    def count(self, dataset_id: str) -> int:
        """Total de registros do dataset (``$select=count(*)``)."""
        return self._client.count(dataset_id)

    # ------------------------------------------------------------------ #
    # Dataset completo (paginado)
    # ------------------------------------------------------------------ #
    def fetch(
        self,
        dataset_id: str,
        *,
        limit: int | None = None,
        offset: int = 0,
        max_records: int | None = None,
    ) -> tuple[list[dict[str, Any]], QueryMetadata]:
        """Busca TODOS os registros crus de um dataset, paginando.

        A paginacao usa ``$order=:id`` estavel ate esgotar o dataset
        (pagina vazia ou ``max_records`` atingido). Retorna dados crus,
        sem filtro de campos nem interpretacao.

        Args:
            dataset_id: ID 4x4 do dataset.
            limit: Registros por pagina (padrao ``self.page_size``).
            offset: Offset inicial (retomada).
            max_records: Teto de registros no total (smoke tests); quando
                None, esgota o dataset.

        Returns:
            ``(records, metadados)`` onde ``records`` e a lista agregada de
            dicts brutos e ``metadados.total`` e o total conhecido (via
            ``count``) quando disponivel.

        Raises:
            SocrataError: falha irrecuperavel apos retries.
        """
        page_limit = limit if limit is not None else self.page_size
        collected: list[dict[str, Any]] = []
        total: int | None = None
        try:
            total = self._client.count(dataset_id)
        except SocrataError as exc:
            logger.warning("count(%s) falhou (%s); seguindo sem total", dataset_id, exc)

        current = offset
        while True:
            if total is not None and current >= total:
                break
            if max_records is not None and len(collected) >= max_records:
                break

            take = page_limit
            if max_records is not None:
                take = min(take, max_records - len(collected))
            if take <= 0:
                break

            page, _meta = self.fetch_page(dataset_id, limit=take, offset=current)
            if not page:
                break

            collected.extend(page)
            current += len(page)
            if len(page) < take:
                break

        meta = QueryMetadata(
            dataset_id=dataset_id,
            offset=offset,
            limit=page_limit,
            total=total,
            truncated=max_records is not None and len(collected) >= (max_records or 0),
        )
        logger.info(
            "SocrataService.fetch(%s): %d registros crus (total=%s, max=%s)",
            dataset_id,
            len(collected),
            total,
            max_records,
        )
        return collected, meta
