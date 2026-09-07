"""Adapters de fontes de dados (camada de integracao multi-fonte).

Este pacote introduz o padrao **Adapter** sobre o pipeline historico do
ENERGY STAR (Socrata). A motivacao e **Dependency Inversion Principle
(DIP)**: o orquestrador (``CollectionService``) passa a depender de uma
interface (``SourceAdapter``) e nao mais de uma implementacao concreta
acoplada a um fornecedor de dados especifico.

Hierarquia:

* :class:`SourceClient` (Protocol) -- transporte HTTP/arquivo: como ler
  registros crus da fonte. Implementacoes: ``EnergyStarClient`` (Socrata),
  ``WattSimpleClient`` (CSV estatico), futuros ``InmetroClient`` (HTML),
  ``IeaClient`` (XLSX).
* :class:`SourceAdapter` (Protocol) -- contrato de dominio: como uma
  linha bruta da fonte vira um produto canonico. Implementacoes:
  ``EnergyStarAdapter`` (1:1 sobre o codigo historico),
  ``WattSimpleAdapter`` (produtos genericos, ``is_generic=True``).

O :class:`SocrataClient` existente em :mod:`collector.api_client`
permanece INTOCADO e passa a ser a implementacao concreta de
``SourceClient`` para a fonte ENERGY STAR. Backward compatibility
preservada (tests existentes continuam usando ``SocrataClient``
diretamente).
"""

from .energy_star import (
    SOURCE_CODE,
    SOURCE_TYPE,
    EnergyStarAdapter,
    EnergyStarClient,
)
from .energy_star import (
    SOURCE_CODE as ENERGY_STAR_SOURCE_CODE,
)
from .energy_star import (
    SOURCE_TYPE as ENERGY_STAR_SOURCE_TYPE,
)
from .iea import SOURCE_CODE as IEA_SOURCE_CODE
from .iea import IeaAdapter, IeaClient
from .inmetro import (
    SOURCE_CODE as INMETRO_SOURCE_CODE,
)
from .inmetro import InmetroAdapter, InmetroClient
from .protocol import RawRecord, SourceAdapter, SourceClient
from .wattsimple import (
    SOURCE_CODE as WATTSIMPLE_SOURCE_CODE,
)
from .wattsimple import (
    SOURCE_TYPE as WATTSIMPLE_SOURCE_TYPE,
)
from .wattsimple import WattSimpleAdapter, WattSimpleClient

__all__ = [
    "ENERGY_STAR_SOURCE_CODE",
    "ENERGY_STAR_SOURCE_TYPE",
    "IEA_SOURCE_CODE",
    "INMETRO_SOURCE_CODE",
    "SOURCE_CODE",  # alias legado de ENERGY_STAR (contrato PR 1)
    "SOURCE_TYPE",  # alias legado de ENERGY_STAR (contrato PR 1)
    "WATTSIMPLE_SOURCE_CODE",
    "WATTSIMPLE_SOURCE_TYPE",
    "EnergyStarAdapter",
    "EnergyStarClient",
    "IeaAdapter",
    "IeaClient",
    "InmetroAdapter",
    "InmetroClient",
    "RawRecord",
    "SourceAdapter",
    "SourceClient",
    "WattSimpleAdapter",
    "WattSimpleClient",
]
