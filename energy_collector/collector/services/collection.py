"""Collection service — owns the fetch → normalize → validate → persist pipeline.

Both the sequential and the concurrent CLI paths funnel through this one
service, so the business rules live in a single place (no duplicated pipeline).
"""

from __future__ import annotations

import asyncio
import logging

from ..config import CATEGORY_SEARCH, KNOWN_DATASETS
from ..database import upsert
from ..normalization import normalize
from ..pagination import iter_pages

logger = logging.getLogger(__name__)


class CollectionService:
    def __init__(self, client, conn) -> None:
        self.client = client
        self.conn = conn

    # ------------------------------------------------------------------ #
    # Dataset resolution
    # ------------------------------------------------------------------ #
    def resolve_dataset_id(self, category: str) -> str | None:
        """Return the Socrata 4x4 id for a logical category.

        Uses the verified mapping first; otherwise asks the live catalogue.
        """
        if category in KNOWN_DATASETS:
            return KNOWN_DATASETS[category]["dataset_id"]
        return self.client.discover_dataset_id(CATEGORY_SEARCH.get(category, category))

    # ------------------------------------------------------------------ #
    # Per-record pipeline (pure — no DB, unit-testable)
    # ------------------------------------------------------------------ #
    def _process(self, raw: dict, category: str):
        """Normalise + validate one record; return ``None`` when rejected."""
        product = normalize(raw, category)
        ok, reason = product.validate()
        if not ok:
            logger.debug("Discarded %s/%s: %s", category, product.source_id, reason)
            return None
        return product

    # ------------------------------------------------------------------ #
    # Persist
    # ------------------------------------------------------------------ #
    def ingest(self, raw_records: list[dict], category: str) -> tuple[int, int]:
        """Normalise, validate and upsert a batch. Returns ``(inserted, updated)``."""
        inserted = updated = 0
        for raw in raw_records:
            product = self._process(raw, category)
            if product is None:
                continue
            if upsert(self.conn, product) == "inserted":
                inserted += 1
            else:
                updated += 1
        return inserted, updated

    # ------------------------------------------------------------------ #
    # Fetch
    # ------------------------------------------------------------------ #
    def fetch_category(
        self, category: str, limit: int | None = None, page_size: int = 1000
    ) -> list[dict]:
        """Fetch every raw record for one category (non-resumable)."""
        dataset_id = self.resolve_dataset_id(category)
        if not dataset_id:
            logger.warning("No dataset found for category '%s'; skipping", category)
            return []
        out: list[dict] = []
        for page in iter_pages(
            self.client,
            dataset_id,
            category,
            page_size=page_size,
            limit=limit,
            resume=False,
        ):
            out.extend(page)
        return out

    # ------------------------------------------------------------------ #
    # Sequential orchestration (resumable)
    # ------------------------------------------------------------------ #
    def collect_category(
        self,
        category: str,
        limit: int | None = None,
        page_size: int = 1000,
        resume: bool = False,
        state_file: str | None = None,
    ) -> tuple[int, int, int]:
        """Fetch + persist one category. Returns ``(received, inserted, updated)``."""
        dataset_id = self.resolve_dataset_id(category)
        if not dataset_id:
            logger.warning("No dataset found for category '%s'; skipping", category)
            return 0, 0, 0

        received = inserted = updated = 0
        for page in iter_pages(
            self.client,
            dataset_id,
            category,
            page_size=page_size,
            limit=limit,
            resume=resume,
            state_file=state_file,
        ):
            received += len(page)
            try:
                with self.conn.transaction():
                    i, u = self.ingest(page, category)
                    inserted += i
                    updated += u
            except Exception as exc:  # roll back this page, then stop the category
                logger.error("Database error while processing %s: %s", category, exc)
                raise
        logger.info(
            "Category %s -> received %d | inserted %d | updated %d",
            category,
            received,
            inserted,
            updated,
        )
        return received, inserted, updated

    # ------------------------------------------------------------------ #
    # Concurrent orchestration
    # ------------------------------------------------------------------ #
    async def _fetch_one(
        self, category: str, limit: int | None, page_size: int, sem: asyncio.Semaphore
    ) -> tuple[str, list[dict]]:
        async with sem:
            raw = await asyncio.to_thread(
                self.fetch_category, category, limit, page_size
            )
        return category, raw

    async def _collect_concurrent(
        self,
        targets: list[str],
        limit: int | None,
        page_size: int,
        max_concurrency: int,
    ) -> tuple[int, int, int]:
        sem = asyncio.Semaphore(max_concurrency)
        tasks = [self._fetch_one(c, limit, page_size, sem) for c in targets]
        received = inserted = updated = 0
        for category, raw in await asyncio.gather(*tasks):
            with self.conn.transaction():
                i, u = self.ingest(raw, category)
            received += len(raw)
            inserted += i
            updated += u
            logger.info(
                "Category %s -> received %d | inserted %d | updated %d",
                category,
                len(raw),
                i,
                u,
            )
        return received, inserted, updated

    def collect_concurrent(
        self,
        targets: list[str],
        limit: int | None = None,
        page_size: int = 1000,
        max_concurrency: int = 4,
    ) -> tuple[int, int, int]:
        """Fetch several categories in parallel, then persist each."""
        return asyncio.run(
            self._collect_concurrent(targets, limit, page_size, max_concurrency)
        )
