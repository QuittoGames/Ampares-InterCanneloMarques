"""Adapter para a fonte ENERGY STAR (Socrata OpenData).

Este modulo implementa :class:`SourceClient` e :class:`SourceAdapter`
para o ENERGY STAR, **reaproveitando** o codigo existente em
:mod:`collector.api_client` (:class:`SocrataClient`,
:class:`RateLimiter`, :class:`SocrataError`) e em
:mod:`collector.normalization` (:func:`normalize_record`,
:func:`slugify_category`).

Decisao arquitetural (PR 1 do plano multi-fonte):

* **Zero quebra de comportamento**. O adapter envolve o codigo atual
  1:1 -- nenhum UUID, nenhum campo calculado, nenhuma chave de
  dedup muda.
* **Backward compatibility**: :class:`SocrataClient` permanece em
  :mod:`collector.api_client` para os testes e o pipeline legados.
  :class:`EnergyStarClient` e um wrapper fino que expoe a mesma
  interface por baixo do contrato :class:`SourceClient`.
* **DIP**: o :class:`CollectionService` pode ser refatorado para
  depender apenas de :class:`SourceClient`/``SourceAdapter``, sem
  importar ``SocrataClient`` diretamente.
"""

from __future__ import annotations

import logging
from collections.abc import Iterator
from decimal import Decimal
from typing import Any, Self

from ..api_client import RateLimiter, SocrataClient, SocrataError
from ..models import NormalizedProduct
from ..normalization import normalize_record, slugify_category
from .protocol import RawRecord

logger = logging.getLogger(__name__)

#: Codigo estavel desta fonte (chave canonica no pipeline multi-fonte).
SOURCE_CODE: str = "ENERGY_STAR"

#: Codigo de tipo: ``individual_product`` -> tabela ``product``.
SOURCE_TYPE: str = "individual_product"


class EnergyStarClient:
    """Adapter de transporte para o ENERGY STAR (Socrata).

    Implementa o contrato :class:`SourceClient` por composicao: delega
    para :class:`SocrataClient` (codigo existente e testado). Nao
    duplica logica de HTTP, retry, rate-limit ou descoberta.

    Attributes:
        code: Constante :data:`SOURCE_CODE` (``"ENERGY_STAR"``).
    """

    def __init__(
        self,
        *,
        app_token: str | None = None,
        base_url: str | None = None,
        catalog_url: str | None = None,
        timeout: float = 60.0,
        max_retries: int = 6,
        rate_limiter: RateLimiter | None = None,
    ) -> None:
        self._inner = SocrataClient(
            app_token=app_token,
            base_url=base_url or "https://data.energystar.gov",  # SOCRATA_BASE default
            catalog_url=catalog_url
            or "https://api.us.socrata.com/api/catalog/v1",  # CATALOG_URL default
            timeout=timeout,
            max_retries=max_retries,
            rate_limiter=rate_limiter,
        )

    @property
    def code(self) -> str:
        return SOURCE_CODE

    # ------------------------------------------------------------------ #
    # SourceClient protocol (DIP)
    # ------------------------------------------------------------------ #
    def fetch_page(
        self, dataset_id: str, *, limit: int, offset: int
    ) -> list[dict[str, Any]]:
        return self._inner.fetch_page(dataset_id, limit=limit, offset=offset)

    def count(self, dataset_id: str) -> int:
        return self._inner.count(dataset_id)

    def discover(self) -> list[tuple[str, str]]:
        return self._inner.discover()

    def close(self) -> None:
        self._inner.close()

    # ------------------------------------------------------------------ #
    # Context manager (espelha SocrataClient)
    # ------------------------------------------------------------------ #
    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    # ------------------------------------------------------------------ #
    # Escape hatch controlado (mantido para o CollectionService legado)
    # ------------------------------------------------------------------ #
    @property
    def inner(self) -> SocrataClient:
        """Acesso direto ao :class:`SocrataClient` (uso restrito).

        Usado pelo :class:`CollectionService` na fase de transicao.
        Sera removido quando o pipeline passar a depender apenas de
        :class:`SourceClient`.
        """
        return self._inner


class EnergyStarAdapter:
    """Adapter de dominio para o ENERGY STAR.

    Implementa o contrato :class:`SourceAdapter` por **delegacao**:
    toda a logica de mapeamento de campos (Socrata -> Product) vive em
    :func:`normalize_record`. Este adapter adiciona apenas a iteracao
    de paginas e o slug de categoria especifico do Socrata.

    Attributes:
        code: Constante :data:`SOURCE_CODE`.
        source_type: Constante :data:`SOURCE_TYPE`.
    """

    code: str = SOURCE_CODE
    source_type: str = SOURCE_TYPE

    def __init__(self, *, client: EnergyStarClient | None = None) -> None:
        self._client = client

    # ------------------------------------------------------------------ #
    # SourceAdapter protocol (DIP)
    # ------------------------------------------------------------------ #
    def iter_raw_records(
        self,
        *,
        dataset_id: str,
        page_size: int,
        start_offset: int = 0,
        limit: int | None = None,
    ) -> Iterator[tuple[int, list[RawRecord]]]:
        """Itera paginas Socrata -> ``RawRecord`` (1:1 com o codigo legado).

        Reaproveita :func:`collector.pagination.iter_pages` para manter
        o comportamento identico ao pipeline atual (paginacao estavel,
        limite opcional, total via ``count``).
        """
        # Importacao local para evitar ciclo: pagination -> api_client.
        from ..pagination import iter_pages

        if self._client is None:
            raise RuntimeError(
                "EnergyStarAdapter requer um EnergyStarClient "
                "(injete via construtor ou use dentro de um contexto)."
            )

        client = self._client.inner  # SocrataClient (escape hatch controlado)
        total: int | None = None
        try:
            total = client.count(dataset_id)
        except SocrataError as exc:
            logger.warning("count(%s) falhou (%s); seguindo sem total", dataset_id, exc)

        for offset, page in iter_pages(
            client,
            dataset_id,
            page_size=page_size,
            start_offset=start_offset,
            total=total,
            limit=limit,
        ):
            yield (
                offset,
                [
                    RawRecord(source_pk=self._extract_source_pk(raw), raw=raw)
                    for raw in page
                ],
            )

    def normalize(
        self,
        raw_record: RawRecord,
        *,
        dataset_id: str,
        category: str,
        tariff_per_kwh: Decimal | None = None,
    ) -> NormalizedProduct | None:
        """Delega 1:1 para :func:`normalize_record` (zero regressao).

        Args:
            raw_record: ``RawRecord`` produzido por :meth:`iter_raw_records`.
            dataset_id: ID 4x4 do dataset (ex.: ``"p5st-her9"``).
            category: Categoria logica do dataset (slug tecnico).
            tariff_per_kwh: Tarifa explicita para o custo derivado
                (nunca assumida arbitrariamente).

        Returns:
            :class:`NormalizedProduct` canonico ou ``None`` quando o
            registro nao tem identificacao minima estavel.
        """
        raw = raw_record.get("raw") or {}
        # ``source=SOURCE_NAME`` garante bit-identical com o pipeline legado.
        return normalize_record(
            raw=raw,
            dataset_id=dataset_id,
            category=category,
            tariff_per_kwh=tariff_per_kwh,
        )

    # ------------------------------------------------------------------ #
    # Helpers internos
    # ------------------------------------------------------------------ #
    @staticmethod
    def _extract_source_pk(raw: dict[str, Any]) -> str:
        """Extrai o identificador estavel na fonte (espelha ``_extract_source_id``).

        Ordem de prioridade (espelha :func:`collector.normalization._extract_source_id`):
        ``pd_id`` -> ``energy_star_model_identifier`` -> ``model_number`` -> ``model``.
        """
        for key in ("pd_id", "energy_star_model_identifier", "model_number", "model"):
            value = raw.get(key)
            if isinstance(value, str):
                stripped = value.strip()
                if stripped:
                    return stripped
            elif value is not None:
                text = str(value).strip()
                if text:
                    return text
        return ""

    @staticmethod
    def slugify_category(dataset_name: str) -> str:
        """Slug tecnico de categoria a partir do titulo do dataset Socrata.

        Reaproveita :func:`collector.normalization.slugify_category` para
        manter o mesmo formato (``"residential_refrigerators"`` etc.).
        """
        return slugify_category(dataset_name)


__all__ = [
    "SOURCE_CODE",
    "SOURCE_TYPE",
    "EnergyStarAdapter",
    "EnergyStarClient",
    "SocrataError",  # re-export para consumidores do adapter
]
