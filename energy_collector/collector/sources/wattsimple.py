"""Adapter para a fonte WattSimple (tabela de potencia generica).

O WattSimple e a fonte de **produtos genericos** do pipeline: linhas com
``categoria -> potencia tipica (W)``, sem marca/modelo/ID de fabricante.
Cada linha vira um ``Product`` com ``is_generic=True`` (D4=A) gravado na
tabela ``product``.

Decisao arquitetural (PR 3 do plano multi-fonte):

* **Transporte isolado**: TODO o acesso a fonte vive em :meth:`WattSimpleClient._fetch_rows`.
  O endpoint oficial fornece CSV com ``appliance``, ``category``,
  ``running_watts``, ``starting_watts`` e ``typical_hours_per_day``.
* **Identidade deterministica**: ``"WATTSIMPLE|{nome}"`` via uuid5. O
  mesmo aparelho generico gera sempre o mesmo UUID (upsert idempotente);
  nomes canonicos (NFKC/casefold) evitam duplicatas por casing.
* **Sem invencao de valores**: potencia faltante => registro descartado
  (log). Nenhuma estimativa e fabricada (principio do normalizador).
* **Colisao impossivel**: prefixo ``WATTSIMPLE`` separa o namespace dos
  UUIDs ENERGY STAR (mesmo nome, outra fonte => outro UUID).
"""

from __future__ import annotations

import csv
import io
import logging
import requests
from collections.abc import Iterator
from decimal import Decimal
from pathlib import Path
from typing import Any

from ..models import NAME_MAX, TEXT_MAX, Product
from ..normalization import _to_decimal, _truncate, slugify_category
from ..taxonomy import resolve_taxonomy
from .protocol import RawRecord
from .api_client import ApiDataClient

logger = logging.getLogger(__name__)

#: Codigo estavel desta fonte (chave canonica no pipeline multi-fonte).
SOURCE_CODE: str = "WATTSIMPLE"
DATASET_ID: str = "wattsimple_appliance_wattage"
DATASET_URL: str = "https://www.wattsimple.com/data/appliance-wattage/csv"

#: Genericos sao produtos individuais (vao para a tabela ``product``).
SOURCE_TYPE: str = "individual_product"

#: Coluna esperada no CSV: nome do tipo de aparelho (ex.: "Geladeira").
_NAME_FIELDS: tuple[str, ...] = ("name", "appliance")

#: Colunas alternativas aceitas para a potencia tipica (em watts).
_POWER_FIELDS: tuple[str, ...] = (
    "avg_power_w",
    "running_watts",
    "power_w",
    "watts",
    "power",
)

#: Colunas alternativas aceitas para consumo anual estimado (kWh).
_ANNUAL_FIELDS: tuple[str, ...] = ("annual_energy_kwh", "annual_kwh", "kwh_year")

#: Traducao nome do aparelho (PT-BR, vocabulario do WattSimple) -> slug
#: taxonomico reconhecido por :func:`collector.taxonomy.resolve_taxonomy`
#: (as keyword rules casam termos em ingles, ex.: ``refrigerat``).
#: Slugs ausentes caem no fallback ``Outros / Nao categorizado``.
_NAME_TO_SLUG: dict[str, str] = {
    "geladeira": "refrigerators",
    "refrigerador": "refrigerators",
    "freezer": "freezer",
    "micro-ondas": "microwave_oven",
    "microondas": "microwave_oven",
    "fogao": "stove",
    "forno": "oven",
    "maquina de lavar": "clothes_washer",
    "lavadora de roupas": "clothes_washer",
    "secadora": "clothes_dryer",
    "lava-loucas": "dishwasher",
    "lavaloucas": "dishwasher",
    "ar-condicionado": "air_conditioner",
    "ar condicionado": "air_conditioner",
    "ventilador": "fan",
    "televisao": "televisions",
    "tv": "televisions",
    "computador": "computer",
    "monitor": "monitor",
    "luminaria": "lighting",
    "lampada": "lighting",
    "chaleira": "kettle",
    "cafeteira": "coffee_maker",
    "torradeira": "toaster",
    "ferro de passar": "iron",
    "aspirador": "vacuum_cleaner",
    "secador de cabelo": "hair_dryer",
    "maquina de lavar loucas": "dishwasher",
}


class WattSimpleClient(ApiDataClient):
    """Transporte da fonte WattSimple (CSV estatico).

    Implementa :class:`SourceClient` por composicao sobre um leitor de
    CSV. O destino (arquivo local ou URL) e injetado: testes usam
    strings in-memory; producao podera apontar para o arquivo real.

    Attributes:
        code: Constante :data:`SOURCE_CODE` (``"WATTSIMPLE"``).
    """

    def __init__(
        self,
        csv_content: str | None = None,
        csv_path: Path | None = None,
        url: str | None = None,
        timeout: float = 30.0,
        session: Any | None = None,
    ) -> None:
        """Fonte de dados: OU conteudo CSV direto (testes), OU path.

        Raises:
            ValueError: se nenhuma fonte foi fornecida.
        """
        if sum(value is not None for value in (csv_content, csv_path, url)) != 1:
            raise ValueError(
                "WattSimpleClient requer exatamente um entre csv_content, "
                "csv_path ou url"
            )
        self._content = csv_content
        self._path = csv_path
        self._url = url
        super().__init__(timeout=timeout, session=session or requests)

    @property
    def code(self) -> str:
        return SOURCE_CODE

    # ------------------------------------------------------------------ #
    # SourceClient protocol (DIP)
    # ------------------------------------------------------------------ #
    def fetch_page(
        self, dataset_id: str, *, limit: int, offset: int
    ) -> list[dict[str, Any]]:
        """Paginacao em memoria: fatia ``_fetch_rows`` por limit/offset.

        ``dataset_id`` e ignorado (fonte de dataset unico) — mantido na
        assinatura pelo contrato :class:`SourceClient`.
        """
        rows = self._fetch_rows()
        return rows[offset : offset + limit]

    def count(self, dataset_id: str) -> int:
        return len(self._fetch_rows())

    def discover(self) -> list[tuple[str, str]]:
        # Fonte estatica de dataset unico: sem sub-datasets.
        return [(DATASET_ID, "WattSimple — tabela de potencia generica")]

    def close(self) -> None:
        # Nada a liberar (dados in-memory ou path).
        pass

    def __enter__(self) -> "WattSimpleClient":
        return self

    def __exit__(self, *_exc_info: object) -> None:
        self.close()

    # ------------------------------------------------------------------ #
    # Transporte real — UNICO ponto de contato com a fonte
    # ------------------------------------------------------------------ #
    def _fetch_rows(self) -> list[dict[str, Any]]:
        """Le o CSV inteiro e devolve linhas como dicts (snake_case).

        O endpoint oficial usa ``appliance`` como nome e
        ``running_watts`` como potência típica. O campo ``starting_watts``
        permanece no raw record: não é média operacional e não deve ser
        copiado para ``avg_power_w``.
        """
        if self._content is not None:
            text = self._content
        elif self._path is not None:
            assert self._path is not None  # garantido no __init__
            text = self._path.read_text(encoding="utf-8")
        else:
            assert self._url is not None
            text = self.get_text(self._url)

        reader = csv.DictReader(io.StringIO(text))
        rows = [
            {(k or "").strip().lower(): v for k, v in row.items()} for row in reader
        ]
        return rows


class WattSimpleAdapter:
    """Adapter de dominio para o WattSimple: linha generica -> Product.

    Diferencas em relacao ao :class:`EnergyStarAdapter`:

    * ``normalize`` monta o :class:`Product` DIRETAMENTE (o normalizador
      historico e especifico do schema Socrata — reaproveita-lo exigiria
      forcar campos inexistentes como marca/modelo).
    * ``is_generic=True`` sempre (D4=A): genericos vivem na tabela
      ``product`` junto aos produtos ENERGY STAR, marcados pela coluna.
    * Reaproveita os helpers puros do normalizador (:func:`_to_decimal`,
      :func:`_truncate`) e a taxonomia global (:func:`resolve_taxonomy`)
      — mesma conversao numerica, mesmas categorias do app.
    """

    code: str = SOURCE_CODE
    source_type: str = SOURCE_TYPE

    def __init__(self, *, client: WattSimpleClient | None = None) -> None:
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
        """Itera paginas do CSV -> ``RawRecord`` (identico ao contrato)."""
        if self._client is None:
            raise RuntimeError(
                "WattSimpleAdapter requer um WattSimpleClient (injete via construtor)."
            )

        rows = self._client.fetch_page(dataset_id, limit=10**9, offset=start_offset)
        if limit is not None:
            rows = rows[:limit]

        # Fatia em paginas de tamanho fixo (contrato do iterator).
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
    ) -> Product | None:
        """Linha generica -> :class:`Product` com ``is_generic=True``.

        Returns:
            ``Product`` com ``source="WATTSIMPLE"``, ``is_generic=True``
            e identidade ``"WATTSIMPLE|{nome}"`` — OU ``None`` quando:
            nome ausente, potencia E consumo anual ausentes, ou valores
            invalidos (descarte logado, sem invencao de valores).
        """
        raw = raw_record.get("raw") or {}
        name = self._extract_name(raw)
        power = self._extract_power(raw)
        annual = self._extract_annual(raw)

        # Identificacao minima: nome + ao menos uma medida energetica.
        if not name or (power is None and annual is None):
            logger.debug(
                "WattSimple: registro descartado (nome=%r, power=%r, annual=%r)",
                name,
                power,
                annual,
            )
            return None

        # Taxonomia global: traduz o nome PT-BR da fonte para o slug
        # taxonomico (vocabulario do pipeline) antes de resolver.
        slug = self._taxonomy_slug(name)
        taxonomy = resolve_taxonomy(slug)

        return Product(
            name=_truncate(name, NAME_MAX, "name"),
            brand=None,  # generico: sem fabricante
            model=None,  # generico: sem modelo
            category=_truncate(taxonomy["category"], TEXT_MAX, "category") or "Outros",
            subcategory=_truncate(taxonomy["subcategory"], TEXT_MAX, "subcategory")
            or "Não categorizado",
            avg_power_w=power,
            annual_energy_kwh=annual,
            standby_power_w=None,  # fonte nao declara standby
            source=SOURCE_CODE,
            source_id=name,  # o nome E o identificador estavel na fonte
            dataset_category=slug,
            dataset_id=SOURCE_CODE,
            is_generic=True,  # D4=A: generico marcado na tabela product
        )

    # ------------------------------------------------------------------ #
    # Helpers internos (espelham o padrao do energy_star.py)
    # ------------------------------------------------------------------ #
    @staticmethod
    def _taxonomy_slug(name: str) -> str:
        """Nome do aparelho -> slug taxonomico do pipeline.

        Ordem: dicionario PT-BR -> EN (ex.: ``geladeira`` ->
        ``refrigerators``); fallback: o proprio nome slugado (nomes
        novos caem em ``Outros / Nao categorizado`` ate mapeamento).
        """
        normalized = name.casefold().strip()
        if normalized in _NAME_TO_SLUG:
            return _NAME_TO_SLUG[normalized]
        return slugify_category(name)

    @staticmethod
    def _extract_source_pk(row: dict[str, Any]) -> str:
        """Chave estavel na fonte: o nome canonicizado do aparelho."""
        name = WattSimpleAdapter._extract_name(row)
        return name or ""

    @staticmethod
    def _extract_name(row: dict[str, Any]) -> str | None:
        for field in _NAME_FIELDS:
            value = row.get(field)
            if value is not None:
                text = str(value).strip()
                if text:
                    return text
        return None

    @staticmethod
    def _extract_power(row: dict[str, Any]) -> Decimal | None:
        for field in _POWER_FIELDS:
            if field in row:
                return _to_decimal(row[field], field)
        return None

    @staticmethod
    def _extract_annual(row: dict[str, Any]) -> Decimal | None:
        for field in _ANNUAL_FIELDS:
            if field in row:
                return _to_decimal(row[field], field)
        return None


__all__ = [
    "SOURCE_CODE",
    "DATASET_ID",
    "DATASET_URL",
    "SOURCE_TYPE",
    "WattSimpleAdapter",
    "WattSimpleClient",
]
