"""Registro de fontes multi-fonte do CLI (PR 6, D8=A).

Fatory central: mapeia o nome de fonte (``--source``) ao par
``(client_factory, adapter_factory, dataset_id_default)``. O CLI
permanece um montador fino — toda a selecao de implementacao concreta
vive AQUI, um unico ponto de mudanca (Open/Closed: nova fonte = nova
entrada, sem tocar o CLI).

Somente fontes com transporte DEFINIDO em producao entram aqui:

* ``energy-star`` — Socrata (legado, 1:1).
* ``wattsimple`` — CSV oficial (estatico).
* ``inmetro`` — XLSX OFICIAL do PBE (transporte real verificado:
  tabela publicada em inmetro.gov.br/CONSUMIDOR/pbe/, parsing stdlib,
  consumo por tensao 127 V/220 V, identidade marca|modelo|registro|
  tensao). IEA permanece fora (workbook real ainda nao verificado).
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from ..api_client import RateLimiter
from .energy_star import EnergyStarAdapter, EnergyStarClient
from .inmetro import DATASET_ID as INMETRO_DATASET_ID
from .inmetro import InmetroAdapter
from .inmetro_xlsx import INMETRO_XLSX_URL, InmetroXlsxClient
from .wattsimple import DATASET_ID as WATTSIMPLE_DATASET_ID
from .wattsimple import DATASET_URL as WATTSIMPLE_DATASET_URL
from .wattsimple import WattSimpleAdapter, WattSimpleClient

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


def build_wattsimple(_app_token: str | None, _rate_per_sec: float) -> SourceSpec:
    """Monta o dataset CSV oficial de aparelhos genéricos WattSimple."""

    def make_client() -> WattSimpleClient:
        return WattSimpleClient(url=WATTSIMPLE_DATASET_URL)

    return {
        "code": "WATTSIMPLE",
        "make_client": make_client,
        "make_adapter": lambda: WattSimpleAdapter(client=make_client()),
        "datasets": [(WATTSIMPLE_DATASET_ID, "WattSimple appliance wattage")],
    }


def build_inmetro(_app_token: str | None, _rate_per_sec: float) -> SourceSpec:
    """Monta a tabela XLSX OFICIAL do PBE (refrigeradores e assemelhados).

    Transporte real verificado (spec secao 2): download do XLSX publicado
    em ``inmetro.gov.br/CONSUMIDOR/pbe/``. O adapter e o mesmo
    ``InmetroAdapter`` (dominio identico do fixture CSV); o cliente XLSX
    achata cada linha da tabela em ate duas observacoes (127 V / 220 V)
    com a tensao ORIGINAL — nenhuma conversao por tensao e aplicada.
    """

    def make_client() -> InmetroXlsxClient:
        return InmetroXlsxClient(url=INMETRO_XLSX_URL)

    return {
        "code": "INMETRO",
        "make_client": make_client,
        "make_adapter": lambda: InmetroAdapter(client=make_client()),
        "datasets": [(INMETRO_DATASET_ID, "INMETRO PBE — Refrigeradores")],
    }


#: Registro de fontes disponiveis no CLI. Chaves = valores de --source.
#: IEA entra quando o workbook real for verificado (ver docstring).
SOURCES: dict[str, Callable[[str | None, float], SourceSpec]] = {
    "energy-star": build_energy_star,
    "inmetro": build_inmetro,
    "wattsimple": build_wattsimple,
}


def available_sources() -> list[str]:
    """Nomes de fontes registradas (para --help e validacao)."""
    return sorted(SOURCES)
