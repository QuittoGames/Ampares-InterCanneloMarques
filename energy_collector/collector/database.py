"""Persistencia INSERT-ONLY no PostgreSQL de producao (spec do banco).

Politica (spec "Especificacao do Banco de Dados — Ampares", secoes 1/6/8):

* O coletor e processo de INGESTAO: conecta ao PostgreSQL de producao via
  configuracao de ambiente (``.env``), normaliza em memoria e executa
  SOMENTE ``INSERT`` nas tabelas autorizadas (``product`` e
  ``product_source_observation``; ENCE e agregados quando a fonte os
  declara).
* INSERT-ONLY: ``ON CONFLICT ... DO NOTHING`` — NUNCA ``DO UPDATE``.
  Reexecucao idempotente: linhas novas sao inseridas, existentes sao
  IGNORADAS como duplicatas; nenhum dado previamente gravado e alterado
  ou apagado. Correcao de catalogo e processo separado e autorizado.
* SEM DDL em runtime: o coletor NAO cria/altera tabelas nem aplica
  migracoes — o esquema e responsabilidade das migracoes versionadas do
  projeto (``migrations/``). :func:`verify_schema` apenas CONFERE, via
  ``information_schema`` (leitura), que as tabelas obrigatorias existem
  antes de qualquer escrita (falha rapida com mensagem clara).
* Lote ORDENADO por UUID antes da escrita — lotes concorrentes travam
  chaves em ordem consistente (anti-deadlock); transacao curta por lote.
* Estatisticas inserted/duplicates por lote: pre-count por
  ``WHERE id = ANY(%s::uuid[])`` — aproximacao estavel sob concorrencia
  (uuid5 torna colisao inter-lote rara e inofensiva ao dado).
* ``users`` e ``registry_user_product`` NUNCA sao tocados (FR-010).
* ``product`` carrega EXATAMENTE as 8 colunas de ``Product.java``;
  proveniencia (fonte, tensao declarada, ``is_generic``, valor/periodo
  brutos de energia) vive em ``product_source_observation``
  (migracoes 004/005).
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from .exceptions import PersistenceError

if TYPE_CHECKING:
    from collections.abc import Sequence

    from psycopg_pool import ConnectionPool

    from .config import DbConfig
    from .models import AggregateRecord, Product

logger = logging.getLogger(__name__)

#: Tabela canonical de destino — escrita SOMENTE com INSERT (spec secao 6).
TABLE = "product"

#: Tabelas que o fluxo de ingestao usa. Verificadas (somente LEITURA de
#: ``information_schema``) antes de qualquer escrita; criadas
#: EXCLUSIVAMENTE pelas migracoes versionadas (``migrations/004``,
#: ``005``, ``006``) — o coletor NUNCA executa DDL.
REQUIRED_TABLES: tuple[str, ...] = (
    "product",
    "product_source_observation",
    "energy_label_class",
    "aggregate_reference",
)

_SCHEMA_CHECK_SQL = (
    "SELECT table_name FROM information_schema.tables "
    "WHERE table_schema = 'public' AND table_name = ANY(%s)"
)

#: Contrato canonico = EXATAMENTE as 8 colunas de ``Product.java``.
#: ``standby_power_w``/``is_generic``/tensao/proveniencia NAO pertencem a
#: ``product`` — vivem em ``product_source_observation`` (004/005).
_INSERT_PRODUCT_SQL = """
INSERT INTO product
    (id, name, brand, model, category, subcategory, avg_power_w, annual_energy_kwh)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (id) DO NOTHING
"""

#: Observacao de fonte: chave natural ``(source, external_id)`` impede
#: ingerir a mesma origem duas vezes; duplicata e IGNORADA (DO NOTHING),
#: nunca atualizada — a observacao ja armazenada permanece intacta.
_INSERT_OBSERVATION_SQL = """
INSERT INTO product_source_observation
    (id, canonical_product_id, source, external_id, brand, model, dataset_id,
     power_w, annual_energy_kwh, standby_power_w, is_generic,
     voltage_raw, voltage_kind, voltage_min_v, voltage_max_v,
     raw_energy_value, raw_energy_unit)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (source, external_id) DO NOTHING
"""

#: ENCE (``energy_label_class``, migracao 006): insert-only tambem.
_INSERT_LABEL_SQL = """
INSERT INTO energy_label_class (id, label_class)
VALUES (%s, %s)
ON CONFLICT (id) DO NOTHING
"""

#: Agregados anonimos (``aggregate_reference``, migracao 006): insert-only.
_INSERT_AGGREGATE_SQL = """
INSERT INTO aggregate_reference
    (id, source, country, ref_year, metric, appliance, value, unit)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (id) DO NOTHING
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


def verify_schema(pool: ConnectionPool) -> None:
    """Confere (somente LEITURA) que as tabelas obrigatorias existem.

    O coletor NAO executa DDL (spec secao 6): criar/evoluir tabelas e
    responsabilidade das migracoes versionadas. Aqui apenas consultamos
    ``information_schema`` e falhamos rapido com orientacao clara quando
    algo esta ausente — evitando gravar por engano em um ambiente sem o
    esquema esperado.

    Raises:
        PersistenceError: erro de infraestrutura ou tabelas ausentes.
    """
    try:
        with pool.connection() as conn:
            rows = conn.execute(_SCHEMA_CHECK_SQL, (list(REQUIRED_TABLES),)).fetchall()
    except Exception as exc:  # psycopg.Error + erros de pool
        raise PersistenceError(f"Falha ao verificar o schema: {exc}") from exc

    found = {row[0] for row in rows}
    missing = [table for table in REQUIRED_TABLES if table not in found]
    if missing:
        raise PersistenceError(
            "Schema incompleto — tabelas ausentes: "
            + ", ".join(missing)
            + ". Aplique as migracoes versionadas do projeto (migrations/); "
            "o coletor nao executa DDL."
        )
    logger.info(
        "Schema verificado: %d tabelas obrigatorias presentes",
        len(REQUIRED_TABLES),
    )


class InsertStats:
    """Contadores de um lote insert-only (relatorio final, FR-011).

    * ``inserted`` — linhas novas gravadas.
    * ``duplicates`` — linhas ignoradas por já existirem
      (``ON CONFLICT DO NOTHING``); nada foi atualizado.
    """

    __slots__ = ("duplicates", "inserted")

    def __init__(self, inserted: int = 0, duplicates: int = 0) -> None:
        self.inserted = inserted
        self.duplicates = duplicates


def insert_batch(pool: ConnectionPool, products: Sequence[Product]) -> InsertStats:
    """Lote INSERT-ONLY idempotente; falha afeta SOMENTE este lote.

    Ordena por UUID (anti-deadlock), pre-conta existentes para estimar
    duplicatas e grava em uma unica transacao curta com
    ``ON CONFLICT (id) DO NOTHING`` — registros existentes NUNCA sao
    atualizados (spec secao 6).

    Raises:
        PersistenceError: erro de infraestrutura do banco traduzido (o
            lote que falha e isolado pelo chamador).
    """
    if not products:
        return InsertStats()

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
        )
        for p in ordered
    ]

    try:
        with pool.connection() as conn, conn.transaction():
            existing = conn.execute(_COUNT_EXISTING_SQL, (ids,)).fetchone()[0]
            conn.execute("SET LOCAL synchronous_commit = OFF")
            with conn.cursor() as cur:
                cur.executemany(_INSERT_PRODUCT_SQL, params)
    except Exception as exc:  # psycopg.Error + erros de pool
        raise PersistenceError(
            f"Falha ao gravar lote de {len(ordered)} produtos: {exc}"
        ) from exc

    duplicates = min(existing, len(ordered))
    return InsertStats(inserted=len(ordered) - duplicates, duplicates=duplicates)


def insert_label_classes(pool: ConnectionPool, products: Sequence[Product]) -> int:
    """Persiste ``Product.label_class`` em ``energy_label_class`` (insert-only).

    Filtra produtos com classe ENCE declarada e grava em lote ordenado
    por UUID (mesma disciplina anti-deadlock). A tabela tem FK para
    ``product``: o chamador DEVE gravar o produto antes (mesma transacao
    ou execucao anterior). Duplicatas sao ignoradas — a classe ja
    armazenada NUNCA e reclassificada por aqui.

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
            cur.executemany(_INSERT_LABEL_SQL, params)
    except Exception as exc:  # psycopg.Error + erros de pool
        raise PersistenceError(
            f"Falha ao gravar {len(params)} classes ENCE: {exc}"
        ) from exc
    return len(params)


def insert_source_observations(
    pool: ConnectionPool, products: Sequence[Product]
) -> int:
    """Persiste cada modelo/registro da fonte ligado ao produto canonico.

    INSERT-ONLY com ``ON CONFLICT (source, external_id) DO NOTHING``:
    a mesma origem re-coletada e ignorada — a observacao ja armazenada
    permanece intacta (rastreabilidade preservada, spec secao 3.4).
    """
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
            observation.is_generic,
            observation.voltage_raw,
            observation.voltage_kind,
            observation.voltage_min_v,
            observation.voltage_max_v,
            observation.raw_energy_value,
            observation.raw_energy_unit,
        )
        for observation in observations
    ]
    try:
        with pool.connection() as conn, conn.transaction(), conn.cursor() as cur:
            cur.executemany(_INSERT_OBSERVATION_SQL, params)
    except Exception as exc:
        raise PersistenceError(
            f"Falha ao gravar {len(params)} observacoes de fonte: {exc}"
        ) from exc
    return len(params)


def insert_aggregates(pool: ConnectionPool, records: Sequence[AggregateRecord]) -> int:
    """Lote INSERT-ONLY de agregados anonimos (IEA -> ``aggregate_reference``).

    Ordena por UUID (anti-deadlock) e grava em transacao curta — mesma
    disciplina de :func:`insert_batch`. Sem pre-count: o relatorio final
    apenas totaliza gravacoes.

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
            cur.executemany(_INSERT_AGGREGATE_SQL, params)
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
