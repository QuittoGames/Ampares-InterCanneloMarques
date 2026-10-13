"""Precedencia de fontes e elegibilidade da projecao canonica (spec secao 4).

Politica de precedencia (documentada em ``energy_collector/docs/data-sources.md``):

* **Primaria — especificacoes de modelos brasileiros**:
  INMETRO/PBE ou especificacoes oficiais de fabricante ligadas a um
  modelo identificavel. SOMENTE registros desta tier podem alimentar os
  valores metricos (``avg_power_w``/``annual_energy_kwh``) da projecao
  canonica persistida na tabela ``product``.
* **Secundaria — especificacoes estrangeiras** (ENERGY STAR e outras
  fontes de outros paises): preservadas como referencia/comparacao via
  ``product_source_observation``; NUNCA agregadas com valores
  brasileiros e nunca sobrescrevem especificacao brasileira verificada.
* **Referencias genericas** (WattSimple e estimativas tipicas de
  aparelhos): permanecem visivelmente genericas (``is_generic=True`` na
  observacao); NUNCA mascaram especificacao de fabricante.
* **Agregados por pais/ano** (IEA): nunca viram produto.

Fontes desconhecidas (nao registradas em nenhuma tier) sao tratadas de
forma CONSERVADORA: nao contribuem para a projecao canonica ate o DEV
classifica-las aqui (decisao de politica, nao do coletor).

Esta tier e tambem o ponto unico onde uma futura fonte oficial de
fabricante brasileira deve ser registrada (ex.: ``"SOMOS"``, codigo de
marca) — adicionar ao frozenset correspondente, sem tocar na logica.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import Product

#: Tier primaria: especificacoes brasileiras por modelo identificavel.
PRIMARY_BR_SOURCES: frozenset[str] = frozenset({"INMETRO"})

#: Tier secundaria: especificacoes estrangeiras (referencia externa).
FOREIGN_SOURCES: frozenset[str] = frozenset(
    {"ENERGY STAR", "ENERGY_STAR", "ENERGYSTAR"}
)

#: Referencias genericas (sem modelo de fabricante).
GENERIC_SOURCES: frozenset[str] = frozenset({"WATTSIMPLE"})

#: Agregados estatisticos por pais/ano — nunca produto.
AGGREGATE_SOURCES: frozenset[str] = frozenset({"IEA"})

#: Fonte sintetica da projecao canonica (saida de ``merge_products``).
CANONICAL_SOURCE: str = "CANONICAL"

TIER_PRIMARY = "primary"
TIER_FOREIGN = "foreign"
TIER_GENERIC = "generic"
TIER_AGGREGATE = "aggregate"
TIER_CANONICAL = "canonical"
TIER_UNKNOWN = "unknown"


def source_tier(source: str | None) -> str:
    """Classifica a fonte segundo a politica de precedencia."""
    if not source:
        return TIER_UNKNOWN
    normalized = source.strip()
    if normalized == CANONICAL_SOURCE:
        return TIER_CANONICAL
    if normalized in PRIMARY_BR_SOURCES:
        return TIER_PRIMARY
    if normalized in FOREIGN_SOURCES:
        return TIER_FOREIGN
    if normalized in GENERIC_SOURCES:
        return TIER_GENERIC
    if normalized in AGGREGATE_SOURCES:
        return TIER_AGGREGATE
    return TIER_UNKNOWN


def is_canonical_eligible(product: Product) -> bool:
    """Registro pode contribuir com metricas da projecao canonica?

    Elegivel somente quando: fonte primaria brasileira E nao generica.
    Estrangeiras, genericas, agregados e fontes desconhecidas nunca
    contribuem com metricas — mas continuam persistidas como observacoes
    de origem (``product_source_observation``).
    """
    if product.is_generic:
        return False
    return source_tier(product.source) == TIER_PRIMARY


__all__ = [
    "AGGREGATE_SOURCES",
    "CANONICAL_SOURCE",
    "FOREIGN_SOURCES",
    "GENERIC_SOURCES",
    "PRIMARY_BR_SOURCES",
    "TIER_AGGREGATE",
    "TIER_CANONICAL",
    "TIER_FOREIGN",
    "TIER_GENERIC",
    "TIER_PRIMARY",
    "TIER_UNKNOWN",
    "is_canonical_eligible",
    "source_tier",
]
