"""Excecoes de dominio do coletor.

Centraliza os tipos de erro que atravessam fronteiras de camada para que os
servicos (camada de aplicacao/orquestracao) possam capturar tipos
especificos em vez de `except Exception`.

A fronteira HTTP/Socrata ja define `SocrataError` em `api_client.py`. Aqui
fica a excecao equivalente da fronteira de persistencia: `database.py`
traduz erros de infraestrutura (`psycopg.Error`) para `PersistenceError`,
impedindo que detalhes do driver vazem para a camada de servico.
"""

from __future__ import annotations


class PersistenceError(Exception):
    """Falha de infraestrutura de banco ja traduzida/tipada.

    Substitui a captura de `psycopg.Error` cru nos servicos: a camada de
    persistencia envolve o erro do driver nesta excecao de dominio, que e
    a unica que o `CollectionService` precisa conhecer.
    """
