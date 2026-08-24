#!/usr/bin/env python3
"""ENERGY STAR data collector (CLI entrypoint / controller).

Thin entrypoint: parses args, wires config → client → DB, and delegates all
fetch/normalise/validate/persist work to :class:`CollectionService`.
"""

from __future__ import annotations

import argparse
import logging
import sys
from logging.handlers import RotatingFileHandler

from collector.api_client import SocrataClient, SocrataError
from collector.config import (
    CATEGORY_SEARCH,
    KNOWN_DATASETS,
    DbConfig,
    SOCRATA_BASE,
    get_app_token,
)
from collector.database import ensure_table, get_connection
from collector.pagination import STATE_FILE
from collector.services.collection import CollectionService

LOG = logging.getLogger("collector")


def setup_logging() -> None:
    LOG.setLevel(logging.DEBUG)
    fmt = logging.Formatter("%(asctime)s %(levelname)-5s %(message)s")

    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.INFO)
    ch.setFormatter(fmt)
    LOG.addHandler(ch)

    fh = RotatingFileHandler(
        "data_collector.log", maxBytes=5_000_000, backupCount=3, encoding="utf-8"
    )
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    LOG.addHandler(fh)


def _targets() -> list[str]:
    """Every collectable category: known datasets plus discovered ones."""
    return list(KNOWN_DATASETS.keys()) + [
        c for c in CATEGORY_SEARCH if c not in KNOWN_DATASETS
    ]


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="ENERGY STAR public data collector")
    p.add_argument("--category", help="single category to collect")
    p.add_argument("--all", action="store_true", help="collect every known category")
    p.add_argument("--limit", type=int, default=None, help="max records per category")
    p.add_argument(
        "--page-size", type=int, default=1000, help="page size for pagination"
    )
    p.add_argument("--resume", action="store_true", help="resume from saved progress")
    p.add_argument("--state-file", default=STATE_FILE, help="resume state file")
    p.add_argument(
        "--concurrent", action="store_true", help="fetch categories in parallel"
    )
    p.add_argument(
        "--max-concurrency",
        type=int,
        default=4,
        help="max categories fetched at once",
    )
    return p


def _report(received: int, inserted: int, updated: int) -> None:
    LOG.info(
        "Collection completed | received %d | inserted %d | updated %d",
        received,
        inserted,
        updated,
    )


def main() -> int:
    setup_logging()
    args = build_parser().parse_args()

    if not args.category and not args.all:
        LOG.error("Nothing to do: provide --category <name> or --all")
        return 2

    try:
        cfg = DbConfig.from_env()
    except RuntimeError as exc:
        LOG.error(str(exc))
        return 1

    token = get_app_token()
    LOG.info("Socrata app token: %s", "present" if token else "absent (anonymous)")

    client = SocrataClient(SOCRATA_BASE, app_token=token)

    try:
        conn = get_connection(cfg)
    except RuntimeError as exc:
        LOG.error(str(exc))
        return 1

    service = CollectionService(client, conn)
    targets = [args.category] if args.category else _targets()

    try:
        ensure_table(conn)

        if args.concurrent:
            received, inserted, updated = service.collect_concurrent(
                targets,
                limit=args.limit,
                page_size=args.page_size,
                max_concurrency=args.max_concurrency,
            )
        else:
            received = inserted = updated = 0
            for category in targets:
                r, i, u = service.collect_category(
                    category,
                    limit=args.limit,
                    page_size=args.page_size,
                    resume=args.resume,
                    state_file=args.state_file,
                )
                received += r
                inserted += i
                updated += u

        _report(received, inserted, updated)
        return 0
    except SocrataError as exc:
        LOG.error("API error: %s", exc)
        return 1
    except Exception as exc:  # noqa: BLE001 - top-level guard, never crash silently
        LOG.exception("Unexpected error: %s", exc)
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
