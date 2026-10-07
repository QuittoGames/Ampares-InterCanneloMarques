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
* Migracao PR-001 (v1.2.0): coluna ``is_generic`` e tabela
  ``energy_specification`` + 4 tabelas auxiliares para rastreabilidade
  de produtos genéricos entre fontes (WattSimple, INMETRO, IEA).
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from .exceptions import PersistenceError

if TYPE_CHECKING:
    from collections.abc import Sequence

    from psycopg_pool import ConnectionPool

    from .config import DbConfig
    from .models import AggregateRecord, Product, SourceObservation, source_observation

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
    standby_power_w   NUMERIC,
    is_generic        BOOLEAN DEFAULT FALSE
)
"""

#: Migracao idempotente para bancos legados (coluna ``is_generic``, D1=A).
_ALTER_IS_GENERIC_SQL = (
    "ALTER TABLE product ADD COLUMN IF NOT EXISTS is_generic BOOLEAN DEFAULT FALSE"
)

#: Migracao idempotente (tabela ``energy_specification``, D3=A): specs tecnicas
#: por fonte, com ID proprio da fonte para rastreabilidade.
_CREATE_ENERGY_SPEC_SQL = """
CREATE TABLE IF NOT EXISTS energy_specification (
    product_id        UUID PRIMARY KEY REFERENCES product(id) ON DELETE CASCADE,
    source            VARCHAR(50) NOT NULL,
    source_product_id VARCHAR(255),
    power_w           NUMERIC,
    efficiency_class  VARCHAR(10),
    declared_year     SMALLINT,
    UNIQUE (source, source_product_id)
)
"""

#: Migracao idempotente (tabela auxiliar 1/4): mapeia ID da fonte -> produto.
_CREATE_SOURCE_PRODUCT_SQL = """
CREATE TABLE IF NOT EXISTS source_product (
    id                UUID PRIMARY KEY REFERENCES product(id) ON DELETE CASCADE,
    source            VARCHAR(50) NOT NULL,
    source_product_id VARCHAR(255) NOT NULL,
    UNIQUE (source, source_product_id)
)
"""

#: Migracao idempotente (tabela auxiliar 2/4): classe de etiqueta INMETRO.
_CREATE_ENERGY_LABEL_CLASS_SQL = """
CREATE TABLE IF NOT EXISTS energy_label_class (
    id                UUID PRIMARY KEY REFERENCES product(id) ON DELETE CASCADE,
    label_class       VARCHAR(10) NOT NULL
                       CHECK (label_class IN ('A++','A+','A','B','C','D','E','F','G')),
    updated_at        TIMESTAMPTZ DEFAULT now()
)
"""

#: Migracao idempotente (tabela auxiliar 3/4): medicoes brutas pre-normalizacao.
_CREATE_ENERGY_RAW_MEASUREMENT_SQL = """
CREATE TABLE IF NOT EXISTS energy_raw_measurement (
    id                UUID PRIMARY KEY REFERENCES product(id) ON DELETE CASCADE,
    raw_power_w       NUMERIC,
    raw_annual_kwh    NUMERIC,
    raw_standby_w     NUMERIC,
    measurement_date  TIMESTAMPTZ DEFAULT now()
)
"""

#: Migracao idempotente (tabela auxiliar 4/4): metadados por fonte (extensivel).
_CREATE_SOURCE_METADATA_SQL = """
CREATE TABLE IF NOT EXISTS source_metadata (
    id                UUID PRIMARY KEY REFERENCES product(id) ON DELETE CASCADE,
    source            VARCHAR(50) NOT NULL,
    metadata_key      VARCHAR(100) NOT NULL,
    metadata_value    TEXT NOT NULL,
    UNIQUE (id, source, metadata_key)
)
"""

#: Migracao idempotente (PR 5, D6=A): dados AGREGADOS e anonimos por
#: pais/ano — referencia estatistica, NAO produto individual. Nao tem FK
#: para ``product``: existe independentemente de catalogo de produtos.
#: Ex.: IEA Household Appliances Database (stock/difusao/energia por
#: aparelho, por pais e ano).
_CREATE_AGGREGATE_REFERENCE_SQL = """
CREATE TABLE IF NOT EXISTS aggregate_reference (
    id        UUID PRIMARY KEY,
    source    VARCHAR(50) NOT NULL,
    country   VARCHAR(100) NOT NULL,
    ref_year  SMALLINT NOT NULL CHECK (ref_year >= 1900),
    metric    VARCHAR(100) NOT NULL,
    appliance VARCHAR(100),
    value     NUMERIC NOT NULL,
    unit      VARCHAR(30) NOT NULL,
    UNIQUE (source, country, ref_year, metric, appliance)
)
"""

_CREATE_SOURCE_OBSERVATION_SQL = """
CREATE TABLE IF NOT EXISTS product_source_observation (
    id UUID PRIMARY KEY,
    canonical_product_id UUID NOT NULL REFERENCES product(id) ON DELETE CASCADE,
    source VARCHAR(50) NOT NULL,
    external_id VARCHAR(255) NOT NULL,
    brand VARCHAR(255),
    model VARCHAR(255),
    dataset_id VARCHAR(255),
    power_w NUMERIC CHECK (power_w IS NULL OR power_w >= 0),
    annual_energy_kwh NUMERIC CHECK (annual_energy_kwh IS NULL OR annual_energy_kwh >= 0),
    standby_power_w NUMERIC CHECK (standby_power_w IS NULL OR standby_power_w >= 0),
    observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source, external_id)
)
"""

_SOURCE_OBSERVATION_UPSERT_SQL = """
INSERT INTO product_source_observation
    (id, canonical_product_id, source, external_id, brand, model, dataset_id,
     power_w, annual_energy_kwh, standby_power_w)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (id) DO UPDATE SET
    canonical_product_id = EXCLUDED.canonical_product_id,
    source = EXCLUDED.source,
    external_id = EXCLUDED.external_id,
    brand = EXCLUDED.brand,
    model = EXCLUDED.model,
    dataset_id = EXCLUDED.dataset_id,
    power_w = EXCLUDED.power_w,
    annual_energy_kwh = EXCLUDED.annual_energy_kwh,
    standby_power_w = EXCLUDED.standby_power_w,
    observed_at = now()
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
     standby_power_w, is_generic)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (id) DO UPDATE SET
    name              = EXCLUDED.name,
    brand             = EXCLUDED.brand,
    model             = EXCLUDED.model,
    category          = EXCLUDED.category,
    subcategory       = EXCLUDED.subcategory,
    avg_power_w       = EXCLUDED.avg_power_w,
    annual_energy_kwh = EXCLUDED.annual_energy_kwh,
    standby_power_w   = EXCLUDED.standby_power_w,
    is_generic        = EXCLUDED.is_generic
"""

_COUNT_EXISTING_SQL = "SELECT count(*) FROM product WHERE id = ANY(%s::uuid[])"


def create_pool(config: DbConfig, max_size: int = 10) -> ConnectionPool:
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


def ensure_table(pool: ConnectionPool) -> None:
    """Garante a tabela ``product`` com o contrato exato (FR-006).

    Idempotente: cria a tabela se ausente e aplica as migracoes de colunas
    em bancos legados (``ADD COLUMN IF NOT EXISTS``) e cria as tabelas
    auxiliares para rastreabilidade de fontes.

    Raises:
        PersistenceError: erro de infraestrutura do banco traduzido.
    """
    try:
        with pool.connection() as conn, conn.transaction():
            conn.execute(_CREATE_SQL)
            conn.execute(_ALTER_SQL)
            conn.execute(_ALTER_STANDBY_SQL)
            conn.execute(_ALTER_IS_GENERIC_SQL)
            conn.execute(_CREATE_ENERGY_SPEC_SQL)
            conn.execute(_CREATE_SOURCE_PRODUCT_SQL)
            conn.execute(_CREATE_ENERGY_LABEL_CLASS_SQL)
            conn.execute(_CREATE_ENERGY_RAW_MEASUREMENT_SQL)
            conn.execute(_CREATE_SOURCE_METADATA_SQL)
            conn.execute(_CREATE_AGGREGATE_REFERENCE_SQL)
            conn.execute(_CREATE_SOURCE_OBSERVATION_SQL)
    except Exception as exc:  # psycopg.Error + erros de pool
        raise PersistenceError(f"Falha ao garantir a tabela '{TABLE}': {exc}") from exc
    logger.info("Tabela '%s' e tabelas auxiliares garantidas", TABLE)


class UpsertStats:
    """Contadores de um upsert em lote (relatorio final, FR-011)."""

    __slots__ = ("inserted", "updated")

    def __init__(self, inserted: int = 0, updated: int = 0) -> None:
        self.inserted = inserted
        self.updated = updated


def upsert_batch(pool: ConnectionPool, products: Sequence[Product]) -> UpsertStats:
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
            p.is_generic,
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


#: Upsert da tabela auxiliar ``energy_label_class`` (PR 2/PR 4):
#: grava a classe ENCE dos produtos que a declaram (INMETRO). Produtos
#: sem ``label_class`` sao simplesmente ignorados (sem erro).
_LABEL_CLASS_UPSERT_SQL = """
INSERT INTO energy_label_class (id, label_class)
VALUES (%s, %s)
ON CONFLICT (id) DO UPDATE SET
    label_class = EXCLUDED.label_class,
    updated_at  = now()
"""


def upsert_label_classes(pool: ConnectionPool, products: Sequence[Product]) -> int:
    """Persiste ``Product.label_class`` em ``energy_label_class`` (PR 4).

    Filtra produtos com classe ENCE declarada e grava em lote ordenado
    por UUID (mesma disciplina anti-deadlock do :func:`upsert_batch`).
    A tabela auxiliar tem FK para ``product``: o chamador DEVE gravar o
    produto antes (mesma transacao ou execucao anterior).

    Returns:
        Numero de classes gravadas (0 quando nenhuma declarada).
    """
    labeled = sorted(
        (p for p in products if p.label_class),
        key=lambda p: p.product_id(),
    )
    if not labeled:
        return 0

    params = [(str(p.product_id()), p.label_class) for p in labeled]
    try:
        with (
            pool.connection() as conn,
            conn.transaction(),
            conn.cursor() as cur,
        ):
            cur.executemany(_LABEL_CLASS_UPSERT_SQL, params)
    except Exception as exc:  # psycopg.Error + erros de pool
        raise PersistenceError(
            f"Falha ao gravar {len(params)} classes ENCE: {exc}"
        ) from exc
    return len(params)


def upsert_source_observations(
    pool: ConnectionPool, products: Sequence[Product]
) -> int:
    """Persiste cada modelo/registro da fonte ligado ao produto canônico."""
    from .models import source_observation

    if not products:
        return 0
    observations = [source_observation(product) for product in products]
    observations.sort(key=lambda observation: observation.id)
    params = [
        (
            str(observation.id),
            str(observation.canonical_product_id),
            observation.source,
            observation.external_id,
            observation.brand,
            observation.model,
            observation.dataset_id,
            observation.power_w,
            observation.annual_energy_kwh,
            observation.standby_power_w,
        )
        for observation in observations
    ]
    try:
        with pool.connection() as conn, conn.transaction(), conn.cursor() as cur:
            cur.executemany(_SOURCE_OBSERVATION_UPSERT_SQL, params)
    except Exception as exc:
        raise PersistenceError(
            f"Falha ao gravar {len(params)} observacoes de fonte: {exc}"
        ) from exc
    return len(params)


#: Upsert da tabela ``aggregate_reference`` (PR 5, D6=A): dados agregados
#: anonimos por pais/ano — referencia estatistica (IEA), nunca ``product``.
_AGGREGATE_UPSERT_SQL = """
INSERT INTO aggregate_reference
    (id, source, country, ref_year, metric, appliance, value, unit)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (id) DO UPDATE SET
    source    = EXCLUDED.source,
    country   = EXCLUDED.country,
    ref_year  = EXCLUDED.ref_year,
    metric    = EXCLUDED.metric,
    appliance = EXCLUDED.appliance,
    value     = EXCLUDED.value,
    unit      = EXCLUDED.unit
"""


def upsert_aggregates(pool: ConnectionPool, records: Sequence[AggregateRecord]) -> int:
    """Upsert idempotente de agregados anonimos (PR 5).

    Ordena por UUID (anti-deadlock) e grava em transacao curta — mesma
    disciplina de :func:`upsert_batch`. Diferenca: sem pre-count de
    estatisticas (agregados sao referencia estatistica; o relatorio
    final apenas totaliza gravacoes).

    Raises:
        PersistenceError: erro de infraestrutura traduzido.
    """
    if not records:
        return 0

    ordered = sorted(records, key=lambda r: r.record_id())
    params = [
        (
            str(r.record_id()),
            r.source,
            r.country,
            r.ref_year,
            r.metric,
            r.appliance,
            r.value,
            r.unit,
        )
        for r in ordered
    ]

    try:
        with (
            pool.connection() as conn,
            conn.transaction(),
            conn.cursor() as cur,
        ):
            cur.executemany(_AGGREGATE_UPSERT_SQL, params)
    except Exception as exc:  # psycopg.Error + erros de pool
        raise PersistenceError(
            f"Falha ao gravar lote de {len(params)} agregados: {exc}"
        ) from exc
    return len(params)


def close_pool(pool: ConnectionPool) -> None:
    """Fecha o pool de forma limpa (fim da varredura)."""
    try:
        pool.close()
    except Exception:
        logger.debug("Falha ao fechar pool", exc_info=True)
