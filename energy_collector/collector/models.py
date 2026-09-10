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
from collections.abc import Sequence

#: Nome canonico da fonte (legacy: usado por testes e como default).
#: **Multi-fonte (PR 1+)**: a chave deterministica passa a usar
#: ``self.source`` (atributo de instancia) em vez deste literal, mas
#: o valor continua sendo ``"ENERGY STAR"`` para preservar os UUIDs
#: existentes BIT-A-BIT. Novas fontes (WattSimple, INMETRO, IEA)
#: injetam seus proprios nomes via :class:`Product.source`.
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
    standby_power_w: Decimal | None
    source: str
    source_id: str | None
    dataset_category: str | None = None
    dataset_id: str | None = None
    is_generic: bool = False
    #: Classe de etiqueta ENCE (``"A"``, ``"B"``, ... ``"G"``) quando a
    #: fonte declara (INMETRO). So em memoria: vai para a tabela auxiliar
    #: ``energy_label_class`` (PR 2), NUNCA no INSERT da tabela ``product``.
    label_class: str | None = None

    # ------------------------------------------------------------------ #
    # Identidade deterministica
    # ------------------------------------------------------------------ #
    def dedup_key(self) -> str:
        """Chave estavel: ``source_id`` vence; fallback usa o slug ORIGINAL
        do dataset (``dataset_category``), nao a taxonomia global — assim a
        identidade do produto sobrevive a remapeamentos de categoria.

        **Multi-fonte (PR 1)**: o prefixo ``self.source`` substitui a
        constante ``SOURCE_NAME``. Para produtos ENERGY STAR, ``source``
        continua sendo o literal ``"ENERGY STAR"`` (atribuido em
        :func:`normalize_record`), de modo que os UUIDs existentes sao
        preservados bit-a-bit. Fontes novas (WattSimple, INMETRO, IEA)
        injetam seu proprio ``source`` no :class:`Product`.
        """
        if self.source_id:
            return f"{self.source}|{canonical(self.source_id)}"
        origin = self.dataset_category or self.category
        return (
            f"{self.source}|{canonical(self.brand)}"
            f"|{canonical(self.model)}|{canonical(origin)}"
        )

    def product_id(self) -> uuid.UUID:
        """UUID5 deterministico — a PK gerada na insercao (FR-004)."""
        return uuid.uuid5(_NAMESPACE, self.dedup_key())

    def canonical_key(self) -> str:
        """Identidade global do tipo de produto, independente da fonte.

        A identidade canônica deliberadamente não inclui marca, modelo ou
        fonte. Assim, ``Geladeira`` do WattSimple e modelos de geladeira do
        INMETRO/ENERGY STAR podem contribuir para a mesma projeção global,
        enquanto continuam preservados como representações de origem.
        """
        return f"{canonical(self.category)}|{canonical(self.subcategory)}"

    def canonical_id(self) -> uuid.UUID:
        """UUID estável da projeção canônica usada por novas cargas."""
        return uuid.uuid5(_NAMESPACE, f"CANONICAL|{self.canonical_key()}")

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

    * ``product`` — a projeção normalizada da fonte. O serviço pode projetá-la
      em um produto canônico antes da escrita; derivados não entram em
      ``product``.
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
    # Potencia em standby (W) extraida da fonte — SOURCE, carregada para
    # rastreabilidade. O consumo em standby completo depende de horas ativas
    # e periodo, que nao sao atributos de catalogo.
    standby_power_w: Decimal | None = None
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


@dataclass(frozen=True, slots=True)
class SourceProductLink:
    """Representação de um produto/modelo em uma fonte específica."""

    source_product_id: uuid.UUID
    product_id: uuid.UUID
    source: str
    external_id: str
    brand: str | None
    model: str | None
    dataset_id: str | None


@dataclass(frozen=True, slots=True)
class SourceObservation:
    """Valor de uma representação de fonte, separado da projeção canônica."""

    id: uuid.UUID
    canonical_product_id: uuid.UUID
    source: str
    external_id: str
    brand: str | None
    model: str | None
    dataset_id: str | None
    power_w: Decimal | None
    annual_energy_kwh: Decimal | None
    standby_power_w: Decimal | None


def source_observation(product: Product) -> SourceObservation:
    external_id = product.source_id or product.dedup_key()
    observation_id = uuid.uuid5(
        _NAMESPACE, f"OBSERVATION|{product.source}|{canonical(external_id)}"
    )
    return SourceObservation(
        id=observation_id,
        canonical_product_id=product.canonical_id(),
        source=product.source,
        external_id=external_id,
        brand=product.brand,
        model=product.model,
        dataset_id=product.dataset_id,
        power_w=product.avg_power_w,
        annual_energy_kwh=product.annual_energy_kwh,
        standby_power_w=product.standby_power_w,
    )


def source_product_link(product: Product) -> SourceProductLink:
    """Converte uma linha de fonte em uma representação persistível."""
    external_id = product.source_id or product.dedup_key()
    source_product_id = uuid.uuid5(
        _NAMESPACE, f"SOURCE_PRODUCT|{product.source}|{canonical(external_id)}"
    )
    return SourceProductLink(
        source_product_id=source_product_id,
        product_id=product.canonical_id(),
        source=product.source,
        external_id=external_id,
        brand=product.brand,
        model=product.model,
        dataset_id=product.dataset_id,
    )


def merge_products(products: Sequence[Product]) -> list[Product]:
    """Cria uma projeção canônica por tipo e calcula médias normalizadas.

    Valores ausentes não participam da média. Os produtos recebidos não são
    alterados; eles continuam disponíveis para persistência como origem.
    """
    from collections import defaultdict

    groups: dict[str, list[Product]] = defaultdict(list)
    for product in products:
        groups[product.canonical_key()].append(product)

    merged: list[Product] = []
    for members in groups.values():
        representative = members[0]
        powers = [p.avg_power_w for p in members if p.avg_power_w is not None]
        annuals = [
            p.annual_energy_kwh for p in members if p.annual_energy_kwh is not None
        ]
        merged.append(
            Product(
                name=representative.subcategory,
                brand=None,
                model=None,
                category=representative.category,
                subcategory=representative.subcategory,
                avg_power_w=(sum(powers, Decimal(0)) / len(powers)) if powers else None,
                annual_energy_kwh=(sum(annuals, Decimal(0)) / len(annuals))
                if annuals
                else None,
                standby_power_w=None,
                source="CANONICAL",
                source_id=representative.canonical_key(),
                dataset_category=representative.subcategory,
                is_generic=False,
                label_class=next(
                    (p.label_class for p in members if p.label_class), None
                ),
            )
        )
    return merged


@dataclass(slots=True)
class AggregateRecord:
    """Dado agregado e ANONIMO (PR 5, D6=A) — referencia estatistica.

    NAO e um produto: e um numero agregado por pais/ano (ex.: consumo
    medio anual de refrigeradores na Franca em 2019, stock de TV por
    populacao no Japao em 2020). Origem tipica: IEA Household Appliances
    Database / Energy End-uses (agregados por pais, sem marca/modelo).

    Destino: tabela ``aggregate_reference`` (PR 5) — nunca ``product``.

    * ``record_id`` — uuid5 deterministico sobre
      ``"{source}|{country}|{year}|{metric}|{appliance}"`` (canonicalizado
      com :func:`canonical`): re-coletas idempotentes, sem colisao entre
      combinacoes pais/ano/metrica.
    * ``appliance`` — opcional (metricas por aparelho); ``None`` para
      agregados de setor inteiro.
    * ``value`` — sempre presente: registro sem valor nao faz sentido
      estatistico e e descartado na origem.
    """

    source: str
    country: str
    ref_year: int
    metric: str
    value: Decimal
    unit: str
    appliance: str | None = None

    def record_id(self) -> uuid.UUID:
        """UUID deterministico (uuid5) da combinacao agregada."""
        key = (
            f"{self.source}"
            f"|{canonical(self.country)}"
            f"|{self.ref_year}"
            f"|{canonical(self.metric)}"
            f"|{canonical(self.appliance)}"
        )
        return uuid.uuid5(_NAMESPACE, key)
