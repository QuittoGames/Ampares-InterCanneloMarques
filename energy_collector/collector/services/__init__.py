"""Subpacote de servicos do coletor (camada Services da arquitetura).

Contem:

* :class:`~collector.services.collection.CollectionService` — orquestra o
  pipeline fetch → normalize → validate → persist nos modos sequencial e
  concorrente.
* :class:`~collector.services.socrata_service.SocrataService` — camada de
  integracao com a API Socrata: traz dados BRUTOS para o nivel do software,
  abstraindo URL/dataset/paginacao/erros HTTP/retries/parsing/metadados.
"""
