"""Persistencia no PostgreSQL (Supabase): pool, garantia de tabela, upsert.

Decisoes da spec refletidas aqui:

* Pool de conexoes (psycopg_pool, psycopg 3) para escrita multi-thread
  sem disputa (FR-007); transacao curta por lote (commit por lote;
  rollback isola falhas — US-3).
* Upsert em lote IDEMPOTENTE (``INSERT ... ON CONFLICT (id) DO UPDATE``):
  registro novo insere, existente atualiza, nunca duplica (FR-005,
  US-2/SC-002). O lote e ORDENADO por UUID antes da escrita — lotes
  concorrentes travam chaves em ordem consistente, evitando deadlock
  (edge case da spec).
* INSERT com as 7 colunas EXPLICITAS do contrato (R7): ``source`` e
  ``source_id`` existem so em memoria e nunca vao ao banco.
* Garantia de estrutura (FR-006): ``CREATE TABLE IF NOT EXISTS product``
  com o contrato exato — sem tocar em outras tabelas (FR-010: NUNCA
  ``userproduct`` nem ``users``).
* Estatisticas inserted/updated por lote: pre-count por
  ``WHERE id = ANY(%s::uuid[])`` — aproximacao estavel sob concorrencia
  (uuid5 torna colisao inter-lote rara e inofensiva ao dado).
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from .exceptions import PersistenceError

if TYPE_CHECKING:
    from collections.abc import Sequence

    from psycopg_pool import ConnectionPool

    from .config import DbConfig
    from .models import Product

logger = logging.getLogger(__name__)

#: Tabela de destino — UNICA tabela escrita pelo coletor (FR-010).
TABLE = "product"

_CREATE_SQL = """
CREATE TABLE IF NOT EXISTS product (
    id                UUID PRIMARY KEY,
    name              VARCHAR(150),
    brand             VARCHAR(255),
    model             VARCHAR(255),
    category          VARCHAR(255),
    subcategory       VARCHAR(255),
    avg_power_w       NUMERIC,
    annual_energy_kwh NUMERIC,
    standby_power_w   NUMERIC
)
"""

#: Migracao idempotente para bancos criados antes da coluna ``subcategory``.
_ALTER_SQL = "ALTER TABLE product ADD COLUMN IF NOT EXISTS subcategory VARCHAR(255)"

#: Migracao idempotente para bancos criados antes da coluna ``standby_power_w``.
_ALTER_STANDBY_SQL = (
    "ALTER TABLE product ADD COLUMN IF NOT EXISTS standby_power_w NUMERIC"
)

#: Contrato de colunas explicitas (R7) — nada de reflexao sobre o dataclass.
_UPSERT_SQL = """
INSERT INTO product
    (id, name, brand, model, category, subcategory, avg_power_w, annual_energy_kwh,
     standby_power_w)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (id) DO UPDATE SET
    name              = EXCLUDED.name,
    brand             = EXCLUDED.brand,
    model             = EXCLUDED.model,
    category          = EXCLUDED.category,
    subcategory       = EXCLUDED.subcategory,
    avg_power_w       = EXCLUDED.avg_power_w,
    annual_energy_kwh = EXCLUDED.annual_energy_kwh,
    standby_power_w   = EXCLUDED.standby_power_w
"""

_COUNT_EXISTING_SQL = "SELECT count(*) FROM product WHERE id = ANY(%s::uuid[])"


def create_pool(config: "DbConfig", max_size: int = 10) -> "ConnectionPool":
    """Cria o pool de conexoes para escrita concorrente (FR-007).

    Args:
        config: Configuracao do banco (vem do .env do projeto pai).
        max_size: Tamanho maximo do pool (escritoras + folga).

    Raises:
        RuntimeError: pool nao conseguiu abrir (falha rapida, mensagem clara).
    """
    from psycopg_pool import ConnectionPool

    try:
        pool = ConnectionPool(
            conninfo=config.conninfo,
            min_size=1,
            max_size=max_size,
            name="energy-collector",
            open=True,
        )
    except Exception as exc:  # psycopg.Error + variantes de pool
        raise RuntimeError(f"Nao foi possivel conectar ao PostgreSQL: {exc}") from exc
    logger.info(
        "Pool de conexoes aberto (host=%s, db=%s, max=%d)",
        config.host,
        config.database,
        max_size,
    )
    return pool


def ensure_table(pool: "ConnectionPool") -> None:
    """Garante a tabela ``product`` com o contrato exato (FR-006).

    Idempotente: cria a tabela se ausente e aplica a migracao da coluna
    ``subcategory`` em bancos legados (``ADD COLUMN IF NOT EXISTS``).

    Raises:
        PersistenceError: erro de infraestrutura do banco traduzido.
    """
    try:
        with pool.connection() as conn, conn.transaction():
            conn.execute(_CREATE_SQL)
            conn.execute(_ALTER_SQL)
            conn.execute(_ALTER_STANDBY_SQL)
    except Exception as exc:  # psycopg.Error + erros de pool
        raise PersistenceError(f"Falha ao garantir a tabela '{TABLE}': {exc}") from exc
    logger.info("Tabela '%s' garantida", TABLE)


class UpsertStats:
    """Contadores de um upsert em lote (relatorio final, FR-011)."""

    __slots__ = ("inserted", "updated")

    def __init__(self, inserted: int = 0, updated: int = 0) -> None:
        self.inserted = inserted
        self.updated = updated


def upsert_batch(pool: "ConnectionPool", products: "Sequence[Product]") -> UpsertStats:
    """Upsert idempotente de um lote; falha afeta SOMENTE este lote.

    Ordena por UUID (anti-deadlock), pre-conta existentes para estatistica
    e grava em uma unica transacao curta.

    Raises:
        PersistenceError: erro de infraestrutura do banco traduzido (o
            lote que falha e isolado pelo chamador).
    """
    if not products:
        return UpsertStats()

    ordered = sorted(products, key=lambda p: p.product_id())
    ids = [str(p.product_id()) for p in ordered]
    params = [
        (
            str(p.product_id()),
            p.name,
            p.brand,
            p.model,
            p.category,
            p.subcategory,
            p.avg_power_w,
            p.annual_energy_kwh,
            p.standby_power_w,
        )
        for p in ordered
    ]

    try:
        with pool.connection() as conn, conn.transaction():
            existing = conn.execute(_COUNT_EXISTING_SQL, (ids,)).fetchone()[0]
            conn.execute("SET LOCAL synchronous_commit = OFF")
            with conn.cursor() as cur:
                cur.executemany(_UPSERT_SQL, params)
    except Exception as exc:  # psycopg.Error + erros de pool
        raise PersistenceError(
            f"Falha ao gravar lote de {len(ordered)} produtos: {exc}"
        ) from exc

    written = len(ordered)
    updated = min(existing, written)
    return UpsertStats(inserted=written - updated, updated=updated)


def close_pool(pool: "ConnectionPool") -> None:
    """Fecha o pool de forma limpa (fim da varredura)."""
    try:
        pool.close()
    except Exception:  # noqa: BLE001 - fechamento nunca quebra o caller
        logger.debug("Falha ao fechar pool", exc_info=True)
