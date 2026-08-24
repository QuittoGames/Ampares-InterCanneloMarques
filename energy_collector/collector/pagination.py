"""Pagination and incremental / resumable fetching.

Yields pages of raw records. Supports:
- configurable page size and global limit
- resume from a saved offset (so an interrupted run can continue)
- progress logging and empty-page detection
"""

from __future__ import annotations

import json
import logging
import os
from typing import Iterator, cast

from .api_client import SocrataClient

logger = logging.getLogger(__name__)

STATE_FILE = ".collector_state.json"


def _load_state(state_file: str) -> dict:
    if not os.path.exists(state_file):
        return {}
    try:
        with open(state_file, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (json.JSONDecodeError, OSError):
        logger.warning("Could not read state file %s; starting fresh", state_file)
        return {}


def _save_state(state_file: str, state: dict) -> None:
    try:
        with open(state_file, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
    except OSError as exc:
        logger.warning("Could not persist state file %s: %s", state_file, exc)


def iter_pages(
    client: SocrataClient,
    dataset_id: str,
    category: str,
    page_size: int = 1000,
    limit: int | None = None,
    resume: bool = False,
    state_file: str | None = STATE_FILE,
) -> Iterator[list[dict]]:
    """Yield pages of raw records for one dataset.

    When ``resume`` is True the last processed offset for the category is read
    from ``state_file`` and iteration continues from there.
    """
    assert not resume or state_file, "resume requires a state_file path"
    sf = cast(str, state_file)
    state = _load_state(sf) if resume else {}
    offset = int(state.get(category, 0)) if resume else 0
    fetched_total = 0
    page_no = (offset // page_size) + 1 if page_size else 1

    logger.info(
        "Category: %s | starting at offset %d (page %d)", category, offset, page_no
    )

    while True:
        page = client.fetch_page(dataset_id, offset, page_size)
        if not page:
            logger.info("Empty page received for %s; stopping", category)
            break

        logger.info("Page %d | fetched %d raw records", page_no, len(page))
        yield page

        fetched_total += len(page)
        offset += len(page)
        page_no += 1

        # Persist progress so a later --resume can continue.
        if resume:
            state[category] = offset
            _save_state(sf, state)

        if limit is not None and fetched_total >= limit:
            logger.info("Reached --limit %d for %s", limit, category)
            break

    if resume:
        # Mark category complete by clearing its cursor.
        state.pop(category, None)
        _save_state(sf, state)
    logger.info(
        "Finished pagination for %s (total fetched: %d)", category, fetched_total
    )
