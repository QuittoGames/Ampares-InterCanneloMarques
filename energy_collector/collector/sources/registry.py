"""Registro de fontes multi-fonte do CLI (PR 6, D8=A).

Fatory central: mapeia o nome de fonte (``--source``) ao par
``(client_factory, adapter_factory, dataset_id_default)``. O CLI
permanece um montador fino — toda a selecao de implementacao concreta
vive AQUI, um unico ponto de mudanca (Open/Closed: nova fonte = nova
entrada, sem tocar o CLI).

Somente fontes com transporte DEFINIDO em producao entram aqui. As
fontes com formato real UNKNOWN (WattSimple, INMETRO, IEA — CSV
injetavel aguardando o download real) ficam de fora do registro
enquanto o acesso real nao for definido pelo DEV: o CLI legado
ENERGY STAR continua sendo o unico caminho de producao.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from ..api_client import RateLimiter
from .energy_star import EnergyStarAdapter, EnergyStarClient

#: Entrada do registro: como montar uma fonte no CLI.
SourceSpec = dict[str, Any]


def build_energy_star(app_token: str | None, rate_per_sec: float) -> SourceSpec:
    """Monta a fonte ENERGY STAR (Socrata) — caminho legado, 1:1.

    O ``EnergyStarClient`` envolve o ``SocrataClient`` historico: mesmo
    transporte, mesmo rate limiter, mesmos defaults. O
    ``CollectionService`` legado NAO e usado aqui — o caminho multi-fonte
    passa pelo :class:`MultiSourceCollectionService` com o adapter 1:1.
    """
    limiter = RateLimiter(rate_per_sec=rate_per_sec)

    def make_client() -> EnergyStarClient:
        return EnergyStarClient(app_token=app_token, rate_limiter=limiter)

    return {
        "code": "ENERGY_STAR",
        "make_client": make_client,
        "make_adapter": lambda: EnergyStarAdapter(client=make_client()),
        "datasets": None,  # varredura do catalogo via discover()
    }


#: Registro de fontes disponiveis no CLI. Chaves = valores de --source.
#: Fontes UNKNOWN (WattSimple/INMETRO/IEA) entram quando o transporte
#: real for definido (ver docstring do modulo).
SOURCES: dict[str, Callable[[str | None, float], SourceSpec]] = {
    "energy-star": build_energy_star,
}


def available_sources() -> list[str]:
    """Nomes de fontes registradas (para --help e validacao)."""
    return sorted(SOURCES)
