"""Pacote ``collector`` — web scraper ENERGY STAR (Socrata) → PostgreSQL.

Arquitetura modular simples (Services, Models, Database), Python 3.14+:

* :mod:`collector.config` — configuracao: DbConfig, catalogo de datasets,
  constantes da API Socrata.
* :mod:`collector.models` — contrato de dados: dataclass ``Product``
  (espelha a tabela ``product`` do banco do projeto Java).
* :mod:`collector.database` — persistencia: pool de conexoes, garantia de
  tabela, upsert em lote idempotente.
* :mod:`collector.api_client` — cliente HTTP Socrata (acesso anonimo,
  retry com recuo exponencial, respeito a ``Retry-After``).
* :mod:`collector.normalization` — normalizacao de registro bruto para
  ``Product`` (mapeamento verificado para datasets conhecidos; heuristica
  generica para desconhecidos).
* :mod:`collector.pagination` — iteracao de paginas estavel + persistencia
  de estado para retomada apos interrupcao.
* :mod:`collector.services.collection` — ``CollectionService``: pipeline
  fetch → normalize → validate → persist, modos sequencial e concorrente.

Decisoes da spec (specs/001-energy-star-scraper/spec.md):
    * Consumidor anonimo da API publica; token app Socrata apenas opcional.
    * Identidade deterministica (uuid5 sobre chave estavel) → idempotencia
      total entre execucoes.
    * Escrita exclusiva na tabela ``product``; NUNCA escrever em
      ``userproduct`` ou ``users`` (FR-010).
    * Metricas ausentes na fonte ficam nulas — nunca inventadas (A2).
"""
