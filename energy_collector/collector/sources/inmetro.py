"""Adapter para a fonte INMETRO — PBE refrigeradores (PR 4, D5=A).

Contexto (evidencia coletada):

* O INMETRO publica tabelas de eficiencia energetica do Programa
  Brasileiro de Etiquetagem (PBE). Refrigeradores possuem **categorias
  oficiais** (Portaria INMETRO 736/2024): 1=degelo manual, 2=Frost Free
  (compart. congelados), 3=refrigerador geral, 4=Combinado, 5=Combinado
  Frost Free, 6=Congelador.
* O consumo e declarado em **kWh/mes** — convertido aqui para
  ``annual_energy_kwh`` (x12) **exatamente uma vez** (spec secao 5).
  Se a fonte ja declarar um valor ANUAL explicito, ele e usado tal qual
  (``raw_energy_unit="kWh/ano"``) e o x12 NUNCA e aplicado — anual e
  mensal nao se confundem. O valor bruto + unidade original ficam em
  ``raw_energy_value``/``raw_energy_unit`` para rastreabilidade.
* Tensao declarada (quando presente nas colunas do PBE) e preservada
  como PROVENIENCIA (``voltage_*`` no Product -> observacao de origem).
  Valores nunca sao convertidos: 110 V, 127 V e 220 V permanecem
  distintos; ausencia fica ``unknown`` (spec secao 3).
* Cada modelo tem classe ENCE (``"A"``..``"G"``), gravada em memoria no
  campo ``Product.label_class`` (destino: tabela auxiliar
  ``energy_label_class`` da PR 2).

Decisao arquitetural (D5=A — "INMETRO refrigerators first"):

* **Escopo**: SOMENTE refrigeradores/assemelhados nesta PR (decisao do
  usuario). Subcategorias ricas derivam da CATEGORIA NUMERICA oficial
  (1-6) — sem fuzzy matching contra outras fontes (D7=A).
* **Transporte isolado**: todo acesso a fonte vive em
  :meth:`InmetroClient._fetch_rows`. O formato real do PBE (sistema
  interativo web + historicos em PDF, alguns XLSX) e UNKNOWN: quando o
  download real for definido, apenas ``_fetch_rows`` muda.
* **Identidade deterministica**: ``"INMETRO|{marca}|{modelo}"`` via
  uuid5 — mesmo produto re-coletado gera o mesmo UUID (idempotente);
  prefixo ``INMETRO`` isola o namespace das outras fontes.
* **Sem cruzamento com ENERGY STAR** (D7=A): um refrigerador Electrolux
  no INMETRO e no ENERGY STAR sao linhas DISTINTAS (UUIDs diferentes por
  prefixo). Unificacao futura, se pedida, usaria a tabela
  ``source_product`` da PR 2 — nunca fuzzy matching automatico.
"""

from __future__ import annotations

import csv
import io
import logging
from collections.abc import Iterator
from decimal import Decimal
from pathlib import Path
from typing import Any

from ..models import NAME_MAX, TEXT_MAX, Product
from ..normalization import _to_decimal, _truncate
from ..taxonomy import resolve_taxonomy
from ..voltage import parse_voltage
from .protocol import RawRecord
from .api_client import ApiDataClient

logger = logging.getLogger(__name__)

#: Codigo estavel desta fonte (chave canonica no pipeline multi-fonte).
SOURCE_CODE: str = "INMETRO"

#: Refrigeradores etiquetados sao produtos individuais (tabela ``product``).
SOURCE_TYPE: str = "individual_product"

#: Dataset unico desta PR: refrigeradores PBE (D5=A).
DATASET_ID: str = "inmetro_refrigerators"

#: Slug taxonomico do dataset — casa ``refrigerat`` na taxonomy global.
_TAXONOMY_SLUG: str = "refrigerators"

#: Meses por ano: consumo PBE e kWh/mes -> anual = mensal x 12 (FACT PBE).
_MONTHS_PER_YEAR: int = 12

#: Categorias oficiais INMETRO (Portaria 736/2024) -> subcategoria do app.
#: Chaves normalizadas: digito puro ("1".."6") ou texto da fonte lowercased.
_CATEGORY_TO_SUBCATEGORY: dict[str, str] = {
    "1": "Geladeira",
    "2": "Frost Free",
    "3": "Geladeira",
    "4": "Combinado",
    "5": "Combinado Frost Free",
    "6": "Congelador",
    # variantes textuais comuns nas tabelas PBE
    "frigobar": "Frigobar",
    "refrigerador": "Geladeira",
    "refrigerador frost-free": "Frost Free",
    "combinado": "Combinado",
    "combinado frost-free": "Combinado Frost Free",
    "side-by-side": "Side-by-side",
    "congelador vertical": "Congelador",
    "congelador horizontal": "Congelador",
}

#: Classes ENCE validas (tabela ``energy_label_class`` da PR 2 usa o
#: mesmo CHECK: 'A+++','A++','A+','A'..'G'). ``A+++`` existe no Padrão
#: 2022 da tabela PBE real (verificado no XLSX oficial).
_VALID_LABELS: frozenset[str] = frozenset(
    {"A+++", "A++", "A+", "A", "B", "C", "D", "E", "F", "G"}
)

#: Colunas alternativas aceitas por campo (formato real UNKNOWN).
_BRAND_FIELDS: tuple[str, ...] = ("brand", "marca", "fabricante")
_MODEL_FIELDS: tuple[str, ...] = ("model", "modelo")
_KWH_MONTH_FIELDS: tuple[str, ...] = (
    "kwh_month",
    "kwh_mes",
    "consumo_kwh_mes",
    "monthly_kwh",
    "monthly_energy_kwh",
)
_CATEGORY_FIELDS: tuple[str, ...] = ("category", "categoria")
_LABEL_FIELDS: tuple[str, ...] = ("label_class", "classe", "etiqueta", "ence")
#: Consumo ANUAL ja declarado pela fonte (kWh/ano) — tem precedencia sobre
#: o mensal e NUNCA passa por x12 (spec secao 5: anual x12 = erro grave).
_ANNUAL_KWH_FIELDS: tuple[str, ...] = (
    "kwh_year",
    "kwh_ano",
    "annual_kwh",
    "annual_energy_kwh",
    "consumo_kwh_ano",
    "consumo_anual_kwh",
)
#: Tensao declarada (aliases PT-BR/EN). Ausente => unknown (nunca inferir).
_VOLTAGE_FIELDS: tuple[str, ...] = (
    "voltage",
    "voltage_v",
    "tensao",
    "tensao_v",
    "tensoes",
    "voltagem",
    "tensao_nominal",
    "tensao_nominal_v",
)
#: Identificador explicito da fonte (tabela PBE real: um N DE REGISTRO
#: pode cobrir VARIOS modelos, entao a identidade usa marca|modelo|tensao
#: quando a fonte declara por tensao — ver InmetroXlsxClient).
#: ATENCAO: a chave "registro" NAO entra aqui — o N de registro e o
#: numero do CERTIFICADO (nao unico por modelo) e nunca e identidade.
_SOURCE_ID_FIELDS: tuple[str, ...] = (
    "source_id",
    "numero_registro",
    "n_de_registro",
    "numero_do_registro",
)


class InmetroClient:
    """Transporte da fonte INMETRO/PBE (CSV estatico injetavel).

    Implementa :class:`SourceClient`. O formato real do PBE e UNKNOWN
    (sistema interativo; historicos em PDF, alguns XLSX): testes injetam
    CSV sintetico; producao apontara o arquivo real quando definido.

    Attributes:
        code: Constante :data:`SOURCE_CODE` (``"INMETRO"``).
    """

    def __init__(
        self, csv_content: str | None = None, csv_path: Path | None = None
    ) -> None:
        if csv_content is None and csv_path is None:
            raise ValueError("InmetroClient requer csv_content ou csv_path")
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
        return [(DATASET_ID, "INMETRO PBE — Refrigeradores")]

    def close(self) -> None:
        pass

    # ------------------------------------------------------------------ #
    # Transporte real — UNICO ponto de contato com a fonte
    # ------------------------------------------------------------------ #
    def _fetch_rows(self) -> list[dict[str, Any]]:
        """Le o CSV e devolve linhas como dicts (chaves lowercased).

        UNKNOWN: contratos internos assumidos por campo (ver
        :data:`_BRAND_FIELDS` etc.). Quando o download real do PBE for
        definido, apenas este metodo muda.
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


class InmetroAdapter:
    """Adapter de dominio INMETRO: linha PBE -> Product com ENCE.

    Diferencas em relacao ao WattSimple (PR 3):

    * Produto **brandado**: ``brand``/``model`` obrigatorios (sem eles,
      registro e descartado) — PBE lista modelos especificos.
    * ``label_class`` (ENCE) validado contra o CHECK da tabela
      ``energy_label_class`` (PR 2) e carregado no Product em memoria.
    * Consumo **kWh/mes -> kWh/ano** (x12): conversao de unidade
      documentada do PBE, nao invencao.
    """

    code: str = SOURCE_CODE
    source_type: str = SOURCE_TYPE

    def __init__(self, *, client: InmetroClient | None = None) -> None:
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
                "InmetroAdapter requer um InmetroClient (injete via construtor)."
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
    ) -> Product | None:
        """Linha PBE -> :class:`Product` (brandado, com ``label_class``).

        Returns:
            ``Product`` com ``source="INMETRO"``, ``annual_energy_kwh``
            convertido de kWh/mes, ``subcategory`` derivada da categoria
            oficial (1-6) — OU ``None`` quando: sem marca OU sem modelo
            OU sem consumo (descarte logado, sem invencao de valores).
        """
        raw = raw_record.get("raw") or {}
        brand = self._extract_first(raw, _BRAND_FIELDS)
        model = self._extract_first(raw, _MODEL_FIELDS)

        # Energia: ANUAL explicito tem precedencia e NUNCA leva x12;
        # somente mensal -> anual (x12 exatamente uma vez). Sem nenhuma
        # declaracao -> descarte (nunca inventar consumo).
        annual, raw_value, raw_unit = self._energy_declaration(raw)

        # Identificacao minima: PBE e brandado — marca+modelo obrigatorios.
        if not brand or not model or annual is None:
            logger.debug(
                "INMETRO: registro descartado (brand=%r, model=%r, energy=%r %r)",
                brand,
                model,
                raw_value,
                raw_unit,
            )
            return None

        # Tensao: apenas preservada (verbatim + interpretacao). NUNCA
        # convertida, NUNCA inferida — fonte sem tensao fica "unknown".
        voltage = parse_voltage(self._extract_first(raw, _VOLTAGE_FIELDS))
        taxonomy = resolve_taxonomy(_TAXONOMY_SLUG)
        subcategory = self._subcategory(raw) or taxonomy["subcategory"]

        name = f"{brand} {model}".strip()

        return Product(
            name=_truncate(name, NAME_MAX, "name"),
            brand=_truncate(brand, TEXT_MAX, "brand"),
            model=_truncate(model, TEXT_MAX, "model"),
            category=taxonomy["category"],
            subcategory=_truncate(subcategory, TEXT_MAX, "subcategory")
            or taxonomy["subcategory"],
            avg_power_w=None,  # PBE nao declara potencia instantanea
            annual_energy_kwh=annual,
            standby_power_w=None,
            source=SOURCE_CODE,
            source_id=self._source_identity(raw, brand, model),
            dataset_category=_TAXONOMY_SLUG,
            dataset_id=DATASET_ID,
            is_generic=False,  # PBE: produto brandado
            label_class=self._extract_label(raw),  # ENCE em memoria
            voltage_raw=voltage.raw,
            voltage_kind=voltage.kind,
            voltage_min_v=voltage.min_v,
            voltage_max_v=voltage.max_v,
            raw_energy_value=raw_value,  # bruto ANTES da conversao x12
            raw_energy_unit=raw_unit,  # unidade/periodo originais
        )

    # ------------------------------------------------------------------ #
    # Helpers internos
    # ------------------------------------------------------------------ #
    @staticmethod
    def _source_identity(raw: dict[str, Any], brand: str, model: str) -> str:
        """Identidade estavel na fonte.

        Fallback: ``marca|modelo`` (UUIDs do fixture CSV preservados).
        A tabela XLSX real declara consumo POR TENSAO — o transporte
        InmetroXlsxClient injeta ``source_id`` explicito
        (``marca|modelo|tensao``) para nao colidir duas variantes de
        tensao do MESMO modelo na chave UNIQUE(source, external_id).
        Um ``N DE REGISTRO`` pode cobrir varios modelos, logo NAO e
        usado como identidade (e proveniencia, nao chave).
        """
        explicit = InmetroAdapter._extract_first(raw, _SOURCE_ID_FIELDS)
        return explicit or f"{brand}|{model}"

    @staticmethod
    def _extract_first(row: dict[str, Any], fields: tuple[str, ...]) -> str | None:
        """Primeiro campo nao-vazio dentre os alias aceitos."""
        for field in fields:
            value = row.get(field)
            if value is None:
                continue
            text = str(value).strip()
            if text:
                return text
        return None

    @staticmethod
    def _energy_declaration(
        row: dict[str, Any],
    ) -> tuple[Decimal | None, Decimal | None, str | None]:
        """Retorna ``(kWh/ano, valor bruto, unidade original)``.

        * Valor ANUAL explicito -> usado tal qual (``"kWh/ano"``); o x12
          NUNCA e aplicado em cima de um valor ja anual.
        * Apenas valor MENSAL -> ``x12`` exatamente uma vez
          (``"kWh/mes"``); o bruto mensal fica em ``raw_energy_value``.
        * Nenhum -> ``(None, None, None)`` — registro descartado pelo
          chamador, sem inventar consumo.
        """
        for field in _ANNUAL_KWH_FIELDS:
            if field in row:
                annual = _to_decimal(row[field], field)
                if annual is not None:
                    return annual, annual, "kWh/ano"
        for field in _KWH_MONTH_FIELDS:
            if field in row:
                monthly = _to_decimal(row[field], field)
                if monthly is not None:
                    annual = InmetroAdapter._annual_from_monthly(monthly)
                    return annual, monthly, "kWh/mes"
        return None, None, None

    @staticmethod
    def _annual_from_monthly(kwh_month: Decimal) -> Decimal:
        """kWh/mes -> kWh/ano (x12, exatamente UMA vez por registro).
        Arredondado a 2 casas como o resto do pipeline (Decimal, sem float)."""
        annual = kwh_month * _MONTHS_PER_YEAR
        return annual.quantize(Decimal("0.01"))

    @staticmethod
    def _extract_label(row: dict[str, Any]) -> str | None:
        """Classe ENCE validada contra o CHECK da tabela auxiliar.

        Valores fora do vocabulario (``"A++"``, .. ``"G"``) viram
        ``None`` (log) — nunca escritos no banco.
        """
        value = InmetroAdapter._extract_first(row, _LABEL_FIELDS)
        if value is None:
            return None
        label = value.upper().strip()
        if label in _VALID_LABELS:
            return label
        logger.debug("INMETRO: classe ENCE invalida descartada: %r", value)
        return None

    @staticmethod
    def _extract_source_pk(row: dict[str, Any]) -> str:
        brand = InmetroAdapter._extract_first(row, _BRAND_FIELDS)
        model = InmetroAdapter._extract_first(row, _MODEL_FIELDS)
        if brand and model:
            return f"{brand}|{model}"
        return ""

    @staticmethod
    def _subcategory(raw: dict[str, Any]) -> str | None:
        """Categoria oficial (1-6 ou texto) -> subcategoria do app."""
        value = InmetroAdapter._extract_first(raw, _CATEGORY_FIELDS)
        if value is None:
            return None
        key = value.strip().lower()
        # digito puro (ex.: "1") ou texto oficial
        if key in _CATEGORY_TO_SUBCATEGORY:
            return _CATEGORY_TO_SUBCATEGORY[key]
        # "Categoria 1", "cat. 1", "1 - Refrigerador..." -> extrai digito
        for part in key.replace("-", " ").split():
            if part.isdigit() and part in _CATEGORY_TO_SUBCATEGORY:
                return _CATEGORY_TO_SUBCATEGORY[part]
        logger.debug("INMETRO: categoria sem mapeamento: %r", value)
        return None


__all__ = [
    "DATASET_ID",
    "SOURCE_CODE",
    "SOURCE_TYPE",
    "InmetroAdapter",
    "InmetroClient",
]
