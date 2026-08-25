"""Iteracao de paginas Socrata e retomada de varredura (resume).

Decisoes da spec refletidas aqui:

* Paginacao completa e DETERMINISTICA (FR-002): ``$limit``/``$offset``
  com ``$order=:id`` (definido no client), ate esgotar o dataset. Quando
  o total e conhecido (count), a varredura para exatamente nele; pagina
  vazia sempre encerra a iteracao.
* Retomada (US-3): progresso por dataset persistido em arquivo de estado
  local (git-ignorado). Valor inteiro = proximo offset; ``"done"`` =
  dataset concluido. Escrita ATOMICA (tmp + os.replace) — interrupcao
  abrupta nao corrompe o estado.
* Idempotencia torna a retomada tolerante a desalinhamento: reprocessar
  uma pagina ja gravada apenas atualiza as mesmas linhas (uuid5).
"""

from __future__ import annotations

import json
import logging
import os
from collections.abc import Iterator
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from .api_client import SocrataClient

logger = logging.getLogger(__name__)

#: Tamanho de pagina padrao — lotes grandes justificados pelo hardware (A7).
DEFAULT_PAGE_SIZE: int = 1000

#: Marcador de dataset concluido no arquivo de estado.
DONE: str = "done"


def iter_pages(
    client: "SocrataClient",
    dataset_id: str,
    page_size: int = DEFAULT_PAGE_SIZE,
    start_offset: int = 0,
    total: int | None = None,
    limit: int | None = None,
) -> Iterator[tuple[int, list[dict[str, Any]]]]:
    """Itera as paginas de um dataset de forma estavel ate o fim.

    Args:
        client: Cliente Socrata (uma instancia por thread).
        dataset_id: ID 4x4 do dataset.
        page_size: Registros por pagina (Socrata aceita ate 50000).
        start_offset: Offset inicial (retomada).
        total: Total conhecido (count(*)); quando informado, limita o loop.
        limit: Teto de registros a fetcher nesta execucao (smoke tests).

    Yields:
        ``(offset_da_pagina, registros_brutos)`` — o offset permite ao
        chamador persistir o progresso apos cada pagina gravada.
    """
    offset = start_offset
    fetched = 0

    while True:
        if total is not None and offset >= total:
            break
        if limit is not None and fetched >= limit:
            break

        page_limit = page_size
        if limit is not None:
            page_limit = min(page_limit, limit - fetched)
        if page_limit <= 0:
            break

        page = client.fetch_page(dataset_id, limit=page_limit, offset=offset)
        if not page:
            logger.info("Pagina vazia em %s (offset %d); fim", dataset_id, offset)
            break

        yield offset, page

        fetched += len(page)
        offset += len(page)
        if len(page) < page_limit:
            # Ultima pagina (menor que o pedido) — dataset esgotado.
            break

    logger.info(
        "Paginacao concluida: %s (inicio=%d, fim=%d, %d registros nesta execucao)",
        dataset_id,
        start_offset,
        offset,
        fetched,
    )


def load_state(path: Path) -> dict[str, Any]:
    """Carrega o estado de retomada (ou estado vazio se inexistente/corrompido)."""
    if not path.exists():
        return {}
    try:
        with path.open("r", encoding="utf-8") as fh:
            state = json.load(fh)
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("Estado ilegivel em %s (%s); recomecando", path, exc)
        return {}
    return state if isinstance(state, dict) else {}


def resume_offset(state: dict[str, Any], dataset_id: str) -> int | None:
    """Offset de retomada de um dataset; ``None`` quando ja esta concluido."""
    value = state.get(dataset_id)
    if value == DONE:
        return None
    if isinstance(value, int) and value > 0:
        return value
    return 0


def save_state(path: Path, state: dict[str, Any]) -> None:
    """Persiste o estado de forma ATOMICA (tmp + replace, US-3)."""
    tmp = path.with_name(path.name + ".tmp")
    try:
        with tmp.open("w", encoding="utf-8") as fh:
            json.dump(state, fh)
        os.replace(tmp, path)
    except OSError as exc:
        logger.warning("Falha ao salvar estado %s: %s", path, exc)


def clear_state(path: Path) -> None:
    """Remove o arquivo de estado apos varredura 100% concluida."""
    try:
        path.unlink(missing_ok=True)
    except OSError as exc:
        logger.warning("Falha ao remover estado %s: %s", path, exc)
