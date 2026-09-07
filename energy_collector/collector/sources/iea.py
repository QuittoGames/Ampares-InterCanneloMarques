"""Adapter para a fonte IEA — agregados anonimos por pais/ano (PR 5, D6=A).

Contexto (evidencia coletada):

* O IEA publica o **Household Appliances Database** (pilot, gratuito,
  XLSX): stock, difusao e penetracao de aparelhos domesticos
  (refrigerators, freezers, clothes washers/dryers, dish washers, ACs,
  PCs, TVs) por pais e ano — 100+ paises, atualizado 2x/ano.
* O Energy End-uses and Efficiency Indicators database traz consumo
  por end-use (PJ) e indicadores (ex.: energia por stock de aparelho).
* Dados ANONIMOS E AGREGADOS: sem marca, sem modelo, sem produto
  individual (D6=A confirmado).

Decisao arquitetural:

* **Nao e produto**: cada linha vira :class:`AggregateRecord` (tabela
  ``aggregate_reference``), nunca :class:`Product` (tabela ``product``).
  O protocolo ``SourceAdapter.source_type`` e ``"aggregate"``.
* **Transporte isolado**: todo acesso a fonte vive em
  :meth:`IeaClient._fetch_rows` (XLSX injetavel; testes usam CSV
  sintetico com o mesmo contrato de colunas).
* **Identidade deterministica**: uuid5 sobre
  ``"IEA|{pais}|{ano}|{metrica}|{aparelho}"`` — re-coleta idempotente.
* **Sem invencao**: valor nao numerico => linha descartada (log). Nao
  convertemos unidades (PJ permanece PJ; o campo ``unit`` preserva).
"""

from __future__ import annotations

import csv
import io
import logging
from collections.abc import Iterator
from decimal import Decimal
from pathlib import Path
from typing import Any

from ..models import AggregateRecord
from ..normalization import _to_decimal
from .protocol import RawRecord

logger = logging.getLogger(__name__)

#: Codigo estavel desta fonte (chave canonica no pipeline multi-fonte).
SOURCE_CODE: str = "IEA"

#: Agregados anonimos NAO sao produtos individuais (D6=A).
SOURCE_TYPE: str = "aggregate"

#: Dataset unico desta PR: Household Appliances Database (pilot).
DATASET_ID: str = "iea_household_appliances"

#: Colunas alternativas aceitas por campo (contrato interno; o XLSX real
#: pode exigir ajuste SOMENTE em :meth:`IeaClient._fetch_rows`).
_COUNTRY_FIELDS: tuple[str, ...] = ("country", "pais", "region", "geo")
_YEAR_FIELDS: tuple[str, ...] = ("year", "ano", "ref_year", "time")
_METRIC_FIELDS: tuple[str, ...] = (
    "metric",
    "indicator",
    "flow",
    "metrica",
    "indicador",
)
_APPLIANCE_FIELDS: tuple[str, ...] = ("appliance", "end_use", "product", "aparelho")
_VALUE_FIELDS: tuple[str, ...] = ("value", "valor", "obs_value", "obs")
_UNIT_FIELDS: tuple[str, ...] = ("unit", "unidade", "units")


class IeaClient:
    """Transporte da fonte IEA (planilha injetavel).

    Implementa :class:`SourceClient`. O arquivo real (XLSX do Household
    Appliances Database) e injetado via path; testes injetam CSV com o
    mesmo contrato de colunas. Quando o download real for definido,
    apenas :meth:`_fetch_rows` muda.

    Attributes:
        code: Constante :data:`SOURCE_CODE` (``"IEA"``).
    """

    def __init__(
        self, csv_content: str | None = None, csv_path: Path | None = None
    ) -> None:
        if csv_content is None and csv_path is None:
            raise ValueError("IeaClient requer csv_content ou csv_path")
        self._content = csv_content
        self._path = csv_path

    @property
    def code(self) -> str:
        return SOURCE_CODE

    # ------------------------------------------------------------------ #
    # SourceClient protocol (DIP)
    # ------------------------------------------------------------------ #
    def fetch_page(
        self, dataset_id: str, *, limit: int, offset: int
    ) -> list[dict[str, Any]]:
        rows = self._fetch_rows()
        return rows[offset : offset + limit]

    def count(self, dataset_id: str) -> int:
        return len(self._fetch_rows())

    def discover(self) -> list[tuple[str, str]]:
        return [(DATASET_ID, "IEA Household Appliances Database")]

    def close(self) -> None:
        pass

    # ------------------------------------------------------------------ #
    # Transporte real — UNICO ponto de contato com a fonte
    # ------------------------------------------------------------------ #
    def _fetch_rows(self) -> list[dict[str, Any]]:
        """Le a planilha e devolve linhas como dicts (chaves lowercased).

        UNKNOWN: o XLSX real do IEA tem estrutura multi-sheet; a leitura
        real (openpyxl) vivera AQUI quando o download for definido.
        Contrato interno: uma linha = um ponto agregado com as colunas
        em :data:`_COUNTRY_FIELDS`..:data:`_UNIT_FIELDS`.
        """
        if self._content is not None:
            text = self._content
        else:
            assert self._path is not None
            text = self._path.read_text(encoding="utf-8")

        reader = csv.DictReader(io.StringIO(text))
        return [
            {(k or "").strip().lower(): v for k, v in row.items()} for row in reader
        ]


class IeaAdapter:
    """Adapter de dominio IEA: linha agregada -> AggregateRecord.

    Diferenca central em relacao as PRs 3/4: ``normalize`` retorna
    :class:`AggregateRecord` (nao :class:`Product`) — o chamador roteia
    pela propriedade ``source_type`` (``"aggregate"``) para a tabela
    ``aggregate_reference``.
    """

    code: str = SOURCE_CODE
    source_type: str = SOURCE_TYPE

    def __init__(self, *, client: IeaClient | None = None) -> None:
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
        if self._client is None:
            raise RuntimeError(
                "IeaAdapter requer um IeaClient (injete via construtor)."
            )

        rows = self._client.fetch_page(dataset_id, limit=10**9, offset=start_offset)
        if limit is not None:
            rows = rows[:limit]

        offset = start_offset
        for i in range(0, len(rows), page_size):
            page = rows[i : i + page_size]
            yield (
                offset,
                [
                    RawRecord(source_pk=self._extract_source_pk(row), raw=row)
                    for row in page
                ],
            )
            offset += len(page)

    def normalize(
        self,
        raw_record: RawRecord,
        *,
        dataset_id: str,
        category: str,
        tariff_per_kwh: Decimal | None = None,
    ) -> AggregateRecord | None:
        """Linha agregada -> :class:`AggregateRecord` (anonimo).

        Returns:
            Registro agregado OU ``None`` quando: pais, ano, metrica ou
            valor ausentes/invalidos (descarte logado — sem invencao).
        """
        raw = raw_record.get("raw") or {}
        country = self._extract_first(raw, _COUNTRY_FIELDS)
        year = self._extract_year(raw)
        metric = self._extract_first(raw, _METRIC_FIELDS)
        value = self._extract_value(raw)
        unit = self._extract_first(raw, _UNIT_FIELDS) or ""
        appliance = self._extract_first(raw, _APPLIANCE_FIELDS)

        # Identificacao minima do ponto agregado.
        if not country or year is None or not metric or value is None:
            logger.debug(
                "IEA: linha descartada (country=%r, year=%r, metric=%r, value=%r)",
                country,
                year,
                metric,
                value,
            )
            return None

        return AggregateRecord(
            source=SOURCE_CODE,
            country=country,
            ref_year=year,
            metric=metric,
            value=value,
            unit=unit,
            appliance=appliance,
        )

    # ------------------------------------------------------------------ #
    # Helpers internos
    # ------------------------------------------------------------------ #
    @staticmethod
    def _extract_first(row: dict[str, Any], fields: tuple[str, ...]) -> str | None:
        for field in fields:
            v = row.get(field)
            if v is None:
                continue
            text = str(v).strip()
            if text:
                return text
        return None

    @staticmethod
    def _extract_year(row: dict[str, Any]) -> int | None:
        """Ano inteiro valido (1900+); textos como '2020' aceitos."""
        text = IeaAdapter._extract_first(row, _YEAR_FIELDS)
        if text is None:
            return None
        try:
            year = int(str(text).strip()[:4])
        except (TypeError, ValueError):
            return None
        return year if year >= 1900 else None

    @staticmethod
    def _extract_value(row: dict[str, Any]) -> Decimal | None:
        text = IeaAdapter._extract_first(row, _VALUE_FIELDS)
        if text is None:
            return None
        return _to_decimal(text, "value")

    @staticmethod
    def _extract_source_pk(row: dict[str, Any]) -> str:
        """Chave estavel na fonte: pais|ano|metrica|aparelho."""
        country = IeaAdapter._extract_first(row, _COUNTRY_FIELDS) or ""
        year = IeaAdapter._extract_year(row)
        metric = IeaAdapter._extract_first(row, _METRIC_FIELDS) or ""
        appliance = IeaAdapter._extract_first(row, _APPLIANCE_FIELDS) or ""
        return f"{country}|{year}|{metric}|{appliance}"


__all__ = [
    "DATASET_ID",
    "SOURCE_CODE",
    "SOURCE_TYPE",
    "IeaAdapter",
    "IeaClient",
]
