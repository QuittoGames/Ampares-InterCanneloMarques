"""PostgreSQL access layer for the product catalogue.

Responsibilities:
- open a connection from resolved config
- ensure the `product` table exists (schema mirrors the JPA Product entity)
- idempotent upsert of appliance *intrinsic* attributes only
- rollback on error (caller controls the transaction boundary)

Design decisions (per project spec):
- The ENERGY STAR API is treated purely as a seed source. We store ONLY the
  intrinsic attributes needed for consumption estimation:
  name, brand, model, category, avg_power_w, annual_energy_kwh.
- No source URL, raw payload, or catalogue metadata is persisted (no raw_data /
  source_url). That would be overengineering for an estimation tool.
- Idempotency: the primary key is a deterministic UUID (uuid5) derived from the
  same dedup key used elsewhere, so re-runs update the same row instead of
  duplicating it.
"""

from __future__ import annotations

import logging

import psycopg

from .config import DbConfig
from .models import Product

logger = logging.getLogger(__name__)

TABLE = "product"


def _with_sslmode(conninfo: str) -> str:
    """Ensure SSL is requested for managed Postgres (Supabase requires it).

    Only added when absent, so a user-supplied ``sslmode`` (e.g. ``disable``
    for local dev) is always respected.
    """
    if "sslmode" in conninfo:
        return conninfo
    if conninfo.startswith(("postgresql://", "postgres://")):
        sep = "&" if "?" in conninfo else "?"
        return f"{conninfo}{sep}sslmode=require"
    return f"{conninfo} sslmode=require"


def get_connection(cfg: DbConfig) -> psycopg.Connection:
    conninfo = _with_sslmode(cfg.conninfo)
    try:
        conn = psycopg.connect(conninfo)
    except psycopg.Error as exc:
        raise RuntimeError(f"Could not connect to PostgreSQL: {exc}") from exc
    return conn


def ensure_table(conn: psycopg.Connection) -> None:
    # Column types mirror the JPA Product entity so the collector can seed the
    # same `product` table the Spring app reads/writes.
    sql = f"""
    CREATE TABLE IF NOT EXISTS {TABLE} (
        id                UUID PRIMARY KEY,
        name              VARCHAR(150),
        brand             VARCHAR(255),
        model             VARCHAR(255),
        category          VARCHAR(255),
        avg_power_w       NUMERIC,
        annual_energy_kwh NUMERIC
    );
    """
    with conn.transaction():
        conn.execute(sql)
    logger.info("Ensured table '%s' exists", TABLE)


def upsert(conn: psycopg.Connection, product: Product) -> str:
    """Insert or update a product. Returns the action: 'inserted' or 'updated'."""
    pid = product.product_id()
    sql = f"""
    INSERT INTO {TABLE}
        (id, name, brand, model, category, avg_power_w, annual_energy_kwh)
    VALUES (%s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        brand = EXCLUDED.brand,
        model = EXCLUDED.model,
        category = EXCLUDED.category,
        avg_power_w = EXCLUDED.avg_power_w,
        annual_energy_kwh = EXCLUDED.annual_energy_kwh
    RETURNING (xmax = 0) AS inserted
    """
    row = conn.execute(
        sql,
        (
            str(pid),
            product.name,
            product.brand,
            product.model,
            product.category,
            product.avg_power_w,
            product.annual_energy_kwh,
        ),
    ).fetchone()
    return "inserted" if row and row[0] else "updated"
