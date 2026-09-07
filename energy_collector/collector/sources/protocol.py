"""Protocolos (interfaces) para a camada de fontes multi-fonte.

Estes protocolos implementam o **Dependency Inversion Principle (DIP)**:
modulos de alto nivel (``CollectionService``, ``normalize_record``) passam
a depender destas abstracoes, e nao mais de classes concretas
acopladas a um fornecedor (ex.: Socrata).

O Python suporta duck-typing nativo, mas ``typing.Protocol`` adiciona
verificacao estatica opcional sem overhead de heranca -- ideal para
adaptadores que podem ser implementados em arquivos isolados.

Hierarquia:

* :class:`SourceClient` -- **transporte**: como ler registros crus.
  Cada fonte concreta (Socrata, HTTP scraping, CSV estatico, XLSX)
  implementa este protocolo.

* :class:`SourceAdapter` -- **dominio**: como uma linha bruta vira um
  :class:`NormalizedProduct` canonico. Cada fonte tem seu proprio
  adapter (mapeamento de campos, escolha de categoria, etc.).

Decisao: ``SourceClient`` e ``SourceAdapter`` sao separados
deliberadamente para que o pipeline concorrente (fetch + write) possa
compartilhar ``SourceClient`` entre fontes diferentes sem misturar
regras de normalizacao.
"""

from __future__ import annotations

from collections.abc import Iterator
from decimal import Decimal
from typing import Any, Protocol, TypedDict, runtime_checkable


class RawRecord(TypedDict, total=False):
    """Estrutura minima de um registro bruto vindo de uma fonte.

    Attributes:
        source_pk: Identificador estavel do registro NA FONTE (ex.: o
            ``pd_id`` do Socrata). Usado como parte da chave deterministica
            do produto (``dedup_key``).
        raw: Linha crua completa conforme recebida da fonte. Preservada
            para auditoria em ``raw_product``.
    """

    source_pk: str
    raw: dict[str, Any]


@runtime_checkable
class SourceClient(Protocol):
    """Transporte de uma fonte: como ler registros crus.

    Esta interface abstrai Socrata, HTTP scraping, CSV estatico e XLSX.
    Implementacoes concretas vivem em arquivos proprios
    (``energy_star.py``, futuros ``wattsimple.py``, etc.).

    O ``CollectionService`` consome esta interface (DIP); nenhuma
    referencia direta a ``SocrataClient`` ou similar deve existir fora
    das implementacoes.
    """

    @property
    def code(self) -> str:
        """Codigo estavel da fonte (ex.: ``"ENERGY_STAR"``)."""
        ...

    def fetch_page(
        self, dataset_id: str, *, limit: int, offset: int
    ) -> list[dict[str, Any]]:
        """Busca uma pagina de registros crus.

        Args:
            dataset_id: Identificador do sub-dataset na fonte (ex.: o
                ID 4x4 do Socrata). Fontes sem sub-datasets usam uma
                chave fixa interna.
            limit: Tamanho maximo da pagina.
            offset: Deslocamento inicial.

        Returns:
            Lista de registros BRUTOS (``dict``). Sem normalizacao.
        """
        ...

    def count(self, dataset_id: str) -> int:
        """Total estimado de registros do sub-dataset (quando aplicavel)."""
        ...

    def discover(self) -> list[tuple[str, str]]:
        """Lista ``(dataset_id, nome_amigavel)`` de sub-datasets.

        Fontes estaticas (CSV/XLSX unico) retornam uma lista vazia ou
        um item fixo.
        """
        ...

    def close(self) -> None:
        """Libera recursos (sessoes HTTP, handles de arquivo)."""
        ...


@runtime_checkable
class SourceAdapter(Protocol):
    """Contrato de dominio: linha bruta -> produto canonico.

    Cada adapter concreto sabe como mapear o schema especifico de sua
    fonte para o contrato universal :class:`NormalizedProduct`.

    Attributes:
        code: Codigo estavel (ex.: ``"ENERGY_STAR"``, ``"WATTSIMPLE"``).
        source_type: ``"individual_product"`` (vai para tabela
            ``product``) ou ``"aggregate"`` (vai para ``aggregate_reference``).
    """

    code: str
    source_type: str

    def iter_raw_records(
        self,
        *,
        dataset_id: str,
        page_size: int,
        start_offset: int = 0,
        limit: int | None = None,
    ) -> Iterator[tuple[int, list[RawRecord]]]:
        """Itera paginas de registros crus a partir de ``start_offset``.

        Yields:
            ``(offset_da_pagina, registros)`` -- o offset permite ao
            chamador persistir progresso de retomada.
        """
        ...

    def normalize(
        self,
        raw_record: RawRecord,
        *,
        dataset_id: str,
        category: str,
        tariff_per_kwh: Decimal | None = None,
    ) -> Any:
        """Linha bruta -> :class:`NormalizedProduct` canonico (ou None).

        Returns ``None`` quando o registro nao tem identificacao minima
        estavel (rejeitado pela camada de normalizacao).
        """
        ...
