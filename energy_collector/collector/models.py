"""Contrato de dados do coletor: dataclass ``Product``.

Espelha a tabela ``product`` do banco do projeto Java (FR-003, FR-006):

* ``id`` UUID — gerado na insercao, de forma DETERMINISTICA a partir da
  chave estavel do registro (uuid5 sobre identificador oficial do modelo
  ou combinacao marca+modelo+categoria) — garante idempotencia entre
  execucoes (FR-004, A4).
* ``name`` VARCHAR(150) — composto marca+modelo quando a fonte separa.
* ``brand`` / ``model`` / ``category`` VARCHAR(255).
* ``avg_power_w`` / ``annual_energy_kwh`` NUMERIC — SOMENTE quando a fonte
  os fornece; ausentes ficam nulos, nunca estimados (A2).
* ``source`` / ``source_id`` — apenas em memoria: alimentam a chave
  deterministica e os logs. NUNCA vao ao banco (contrato de 7 colunas).

Canonicalizacao da chave (revisao de seguranca R8): NFKC + casefold +
colapso de whitespace em cada componente, separador fixo ``|`` — o mesmo
produto nao gera UUIDs diferentes por variacao de case/espacos.
"""

from __future__ import annotations

import unicodedata
import uuid
from dataclasses import dataclass
from decimal import Decimal

#: Nome canonico da fonte (componente fixo da chave deterministica).
SOURCE_NAME: str = "ENERGY STAR"

#: Limites do contrato da tabela ``product`` (espelham o DDL/JPA).
NAME_MAX: int = 150
TEXT_MAX: int = 255

#: Namespace estavel: mesma chave => mesmo UUID entre execucoes/maquinas.
_NAMESPACE: uuid.UUID = uuid.NAMESPACE_URL


def canonical(value: str | None) -> str:
    """Canonicaliza um componente da chave deterministica (R8).

    NFKC normaliza formas Unicode; casefold dobra case; whitespace e
    colapsado. Entrada vazia/None => string vazia.
    """
    if not value:
        return ""
    normalized = unicodedata.normalize("NFKC", str(value)).casefold()
    return " ".join(normalized.split())


@dataclass(slots=True)
class Product:
    """Produto normalizado, pronto para upsert idempotente em ``product``.

    * ``category`` / ``subcategory`` — taxonomia GLOBAL da aplicacao
      (``collector.taxonomy``); vao ao banco e alimentam consultas.
    * ``dataset_category`` — slug tecnico do dataset de origem (ex.:
      ``"televisions"``); NAO vai ao banco: preserva rastreabilidade e
      ancora a chave deterministica, desacoplando a identidade do produto
      da evolucao da taxonomia.
    * ``dataset_id`` — 4x4 do dataset de origem; NAO vai ao banco.
    """

    name: str | None
    brand: str | None
    model: str | None
    category: str
    subcategory: str
    avg_power_w: Decimal | None
    annual_energy_kwh: Decimal | None
    source: str
    source_id: str | None
    dataset_category: str | None = None
    dataset_id: str | None = None

    # ------------------------------------------------------------------ #
    # Identidade deterministica
    # ------------------------------------------------------------------ #
    def dedup_key(self) -> str:
        """Chave estavel: ``source_id`` vence; fallback usa o slug ORIGINAL
        do dataset (``dataset_category``), nao a taxonomia global — assim a
        identidade do produto sobrevive a remapeamentos de categoria."""
        if self.source_id:
            return f"{SOURCE_NAME}|{canonical(self.source_id)}"
        origin = self.dataset_category or self.category
        return (
            f"{SOURCE_NAME}|{canonical(self.brand)}"
            f"|{canonical(self.model)}|{canonical(origin)}"
        )

    def product_id(self) -> uuid.UUID:
        """UUID5 deterministico — a PK gerada na insercao (FR-004)."""
        return uuid.uuid5(_NAMESPACE, self.dedup_key())

    # ------------------------------------------------------------------ #
    # Regras de dominio (SC-004)
    # ------------------------------------------------------------------ #
    def validate(self) -> tuple[bool, str | None]:
        """Retorna ``(is_valid, motivo)``. Nunca inventa valor.

        Rejeita somente registro sem identificacao estavel minima — a
        limpeza de metricas ruins (negativo/NaN/Inf -> NULL) ja acontece
        na normalizacao, sem descartar o produto inteiro.
        """
        if not self.source_id and not (self.brand and self.model):
            return False, "sem identificador estavel (source_id ou brand+model)"
        if not self.category:
            return False, "category vazia"
        return True, None


def stable_uuid(product: Product) -> uuid.UUID:
    """Atalho de modulo (assinatura definida no scaffold): ``product_id``."""
    return product.product_id()


@dataclass(slots=True)
class NormalizedProduct:
    """Produto normalizado + rastreabilidade de fonte e derivados.

    Separa explicitamente tres grupos de dados (requisito de
    rastreabilidade do normalizer):

    * ``product`` — o :class:`Product` canônico, unico objeto que vai ao
      banco (contrato de escrita de 8 colunas). NUNCA carrega derivados.
    * ``raw_*`` — SOURCE DATA: valores BRUTOS vindos da API, preservados
      sem alteracao para auditoria (``raw_power`` e ``raw_annual_energy``).
    * ``equivalent_*`` / ``estimated_*`` — DERIVED DATA: valores calculados
      deterministicamente a partir dos dados de origem (ver
      :mod:`collector.normalization`). Nunca inventados.

    O normalizer nunca sobrescreve o valor original: se um derivado nao
    puder ser calculado com seguranca (campo ausente, divisao por zero,
    tarifa ausente), ele fica ``None`` — o registro continua representado
    por ``product``.
    """

    product: Product
    # SOURCE DATA — valores brutos da API (rastreabilidade).
    raw_power: Decimal | None = None
    raw_annual_energy: Decimal | None = None
    # DERIVED DATA — calculos determinísticos a partir dos dados.
    equivalent_hours_year: Decimal | None = None
    equivalent_hours_year_day: Decimal | None = None
    estimated_daily_energy_kwh: Decimal | None = None
    estimated_cost: Decimal | None = None
    # Tarifa (moeda/kWh) efetivamente usada nos calculos, quando aplicavel.
    tariff_per_kwh: Decimal | None = None

    # ------------------------------------------------------------------ #
    # Atalhos para os campos canonicos (evita `record.product.avg_power_w`)
    # ------------------------------------------------------------------ #
    @property
    def avg_power_w(self) -> Decimal | None:
        return self.product.avg_power_w

    @property
    def annual_energy_kwh(self) -> Decimal | None:
        return self.product.annual_energy_kwh

    @property
    def source_id(self) -> str | None:
        return self.product.source_id
