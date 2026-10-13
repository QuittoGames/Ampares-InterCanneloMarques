"""Testes unitarios de ``collector.database`` (politica INSERT-ONLY).

Tudo com pool falso (``MagicMock``): nenhum teste toca rede ou banco reais.

Cobre (spec "Especificacao do Banco de Dados", secoes 6/8/9):

* ``verify_schema`` — somente LEITURA de ``information_schema``; NUNCA
  executa DDL; falha rapida com orientacao para migracoes.
* INSERT-ONLY — todos os INSERTs usam ``ON CONFLICT ... DO NOTHING``;
  nenhum ``DO UPDATE`` em lugar algum do modulo.
* ``insert_batch`` — 8 colunas EXATAS (``Product.java``); ordenacao por
  UUID; estatistica inserted/duplicates via pre-count.
* ``insert_source_observations`` — proveniencia (genericidade, tensao,
  valor/periodo brutos) e chave natural ``(source, external_id)``.
* ``InsertStats`` — contrato do relatorio inserted/duplicates.
"""

from __future__ import annotations

import dataclasses
from decimal import Decimal
from unittest.mock import MagicMock

import pytest

import collector.database as database_module
from collector.database import (
    _COUNT_EXISTING_SQL,
    _INSERT_AGGREGATE_SQL,
    _INSERT_LABEL_SQL,
    _INSERT_OBSERVATION_SQL,
    _INSERT_PRODUCT_SQL,
    _SCHEMA_CHECK_SQL,
    InsertStats,
    REQUIRED_TABLES,
    insert_aggregates,
    insert_batch,
    insert_label_classes,
    insert_source_observations,
    verify_schema,
)
from collector.exceptions import PersistenceError
from collector.models import AggregateRecord

from .conftest import make_fake_pool, make_product

# ------------------------------------------------------------------ #
# verify_schema — somente leitura; NUNCA DDL
# ------------------------------------------------------------------ #


def _pool_with_tables(tables: list[str]) -> tuple[MagicMock, MagicMock]:
    pool, conn, _cursor = make_fake_pool()
    conn.execute.return_value.fetchall.return_value = [(t,) for t in tables]
    return pool, conn


class TestVerifySchema:
    def test_passes_when_all_required_tables_exist(self) -> None:
        pool, conn = _pool_with_tables(list(REQUIRED_TABLES))

        verify_schema(pool)  # nao levanta

        sql, params = conn.execute.call_args.args
        assert sql == _SCHEMA_CHECK_SQL
        assert set(params[0]) == set(REQUIRED_TABLES)

    def test_missing_table_fails_with_migration_guidance(self) -> None:
        pool, _conn = _pool_with_tables(["product"])  # sem as demais

        with pytest.raises(PersistenceError, match="migracoes"):
            verify_schema(pool)

    def test_db_failure_is_translated(self) -> None:
        pool, conn = _pool_with_tables([])
        conn.execute.side_effect = RuntimeError("db down")

        with pytest.raises(PersistenceError, match="verificar o schema"):
            verify_schema(pool)

    def test_collector_never_executes_ddl(self) -> None:
        # O coletor nao cria/altera tabelas (spec secao 6): nenhuma
        # constante SQL do modulo contem CREATE/ALTER/DROP/TRUNCATE.
        sqls = [
            value
            for name, value in vars(database_module).items()
            if name.startswith("_") and name.endswith("_SQL") and isinstance(value, str)
        ]
        assert sqls, "constantes SQL esperadas"
        for sql in sqls:
            for forbidden in ("CREATE TABLE", "ALTER TABLE", "DROP ", "TRUNCATE"):
                assert forbidden not in sql, forbidden

    def test_insert_only_everywhere(self) -> None:
        # Politica solicitada: DO NOTHING, nunca DO UPDATE (spec secoes 1/6).
        for sql in (
            _INSERT_PRODUCT_SQL,
            _INSERT_OBSERVATION_SQL,
            _INSERT_LABEL_SQL,
            _INSERT_AGGREGATE_SQL,
        ):
            assert "DO NOTHING" in sql
            assert "DO UPDATE" not in sql


# ------------------------------------------------------------------ #
# insert_batch — contrato canonico de 8 colunas (Product.java)
# ------------------------------------------------------------------ #


class TestInsertBatch:
    def test_row_has_exactly_eight_canonical_columns(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        branded = make_product(source_id="A-1", is_generic=False)
        generic = make_product(source_id="A-2", is_generic=True)

        insert_batch(pool, [branded, generic])

        # executemany recebe [(id, name, brand, model, cat, subcat,
        # power, annual), ...] ordenado por UUID — SEM is_generic/standby.
        assert cursor.executemany.called
        params = cursor.executemany.call_args.args[1]
        assert len(params) == 2
        assert all(len(row) == 8 for row in params)

    def test_provenance_never_reaches_product_table(self) -> None:
        pool, _conn, cursor = make_fake_pool()

        insert_batch(pool, [make_product(source_id="A-1", is_generic=True)])

        assert "is_generic" not in _INSERT_PRODUCT_SQL
        assert "standby_power_w" not in _INSERT_PRODUCT_SQL
        assert "voltage" not in _INSERT_PRODUCT_SQL

    def test_should_map_param_row_to_matching_product(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        p1 = make_product(source_id="A-1", power=Decimal("100"))
        p2 = make_product(source_id="A-2", power=Decimal("200"))

        insert_batch(pool, [p1, p2])

        params = cursor.executemany.call_args.args[1]
        by_id = {str(p.product_id()): p for p in (p1, p2)}
        for row in params:
            product = by_id[row[0]]
            assert row[6] == product.avg_power_w
            assert row[7] == product.annual_energy_kwh

    def test_should_sort_by_uuid_before_write(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        p1 = make_product(source_id="ZZZ-1")
        p2 = make_product(source_id="AAA-2")

        insert_batch(pool, [p1, p2])

        params = cursor.executemany.call_args.args[1]
        assert params[0][0] < params[1][0]  # ids ordenados asc

    def test_should_return_empty_stats_for_empty_batch(self) -> None:
        pool, _conn, _cursor = make_fake_pool()

        stats = insert_batch(pool, [])

        assert stats.inserted == 0
        assert stats.duplicates == 0

    def test_should_count_inserted_and_duplicates(self) -> None:
        pool, _conn, _cursor = make_fake_pool(existing=1)
        products = [
            make_product(source_id="A-1"),
            make_product(source_id="A-2"),
        ]

        stats = insert_batch(pool, products)

        # 1 linha nova + 1 duplicata ignorada (DO NOTHING, sem update).
        assert stats.inserted == 1
        assert stats.duplicates == 1

    def test_should_translate_db_error_to_persistence_error(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        cursor.executemany.side_effect = RuntimeError("db down")

        with pytest.raises(PersistenceError):
            insert_batch(pool, [make_product()])

    def test_should_pass_decimals_untouched(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        products = [
            make_product(
                source_id="A-1",
                power=Decimal("150.0"),
                annual=Decimal("420.00"),
            )
        ]

        insert_batch(pool, products)

        row = cursor.executemany.call_args.args[1][0]
        assert row[6] == Decimal("150.0")
        assert row[7] == Decimal("420.00")

    def test_pre_count_targets_ids_not_names(self) -> None:
        pool, conn, _cursor = make_fake_pool(existing=0)

        insert_batch(pool, [make_product(source_id="A-1")])

        assert conn.execute.call_args_list[0].args[0] == _COUNT_EXISTING_SQL


# ------------------------------------------------------------------ #
# InsertStats
# ------------------------------------------------------------------ #


class TestInsertStatsContract:
    def test_should_default_to_zero(self) -> None:
        stats = InsertStats()
        assert stats.inserted == 0
        assert stats.duplicates == 0

    def test_should_hold_values(self) -> None:
        stats = InsertStats(inserted=3, duplicates=5)
        assert stats.inserted == 3
        assert stats.duplicates == 5


# ------------------------------------------------------------------ #
# insert_label_classes — ENCE (insert-only)
# ------------------------------------------------------------------ #


class TestInsertLabelClasses:
    def test_should_write_only_labeled_products(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        products = [
            make_product(source_id="A-1", label_class="A"),
            make_product(source_id="A-2", label_class=None),  # ignorado
        ]

        written = insert_label_classes(pool, products)

        assert written == 1
        params = cursor.executemany.call_args.args[1]
        assert len(params) == 1
        assert params[0][1] == "A"

    def test_should_return_zero_for_no_labels(self) -> None:
        pool, _conn, cursor = make_fake_pool()

        written = insert_label_classes(pool, [make_product()])

        assert written == 0
        cursor.executemany.assert_not_called()

    def test_should_return_zero_for_empty_batch(self) -> None:
        pool, _conn, _cursor = make_fake_pool()

        assert insert_label_classes(pool, []) == 0

    def test_should_sort_by_uuid_before_write(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        p1 = make_product(source_id="ZZZ-1", label_class="B")
        p2 = make_product(source_id="AAA-2", label_class="A")

        insert_label_classes(pool, [p1, p2])

        params = cursor.executemany.call_args.args[1]
        assert params[0][0] < params[1][0]

    def test_label_class_is_never_reclassified(self) -> None:
        # Insert-only: sem updated_at/DO UPDATE — a classe ja gravada
        # permanece; re-classificacao e processo autorizado a parte.
        assert "DO NOTHING" in _INSERT_LABEL_SQL
        assert "DO UPDATE" not in _INSERT_LABEL_SQL
        assert "updated_at" not in _INSERT_LABEL_SQL

    def test_should_translate_errors_to_persistence_error(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        cursor.executemany.side_effect = RuntimeError("db down")

        with pytest.raises(PersistenceError):
            insert_label_classes(pool, [make_product(label_class="A")])


# ------------------------------------------------------------------ #
# insert_source_observations — proveniencia (005) + chave natural
# ------------------------------------------------------------------ #


class TestInsertSourceObservations:
    def test_row_carries_provenance_fields(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        product = make_product(source_id="A-1", is_generic=True)
        generic = dataclasses.replace(product, voltage_raw="220 V")
        generic = dataclasses.replace(
            generic,
            voltage_kind="monovolt",
            voltage_min_v=Decimal("220"),
            voltage_max_v=Decimal("220"),
            raw_energy_value=Decimal("30"),
            raw_energy_unit="kWh/mes",
        )

        written = insert_source_observations(pool, [generic])

        assert written == 1
        row = cursor.executemany.call_args.args[1][0]
        assert len(row) == 17
        assert row[10] is True  # is_generic
        assert row[11] == "220 V"  # voltage_raw (verbatim)
        assert row[12] == "monovolt"
        assert row[13] == Decimal("220")
        assert row[14] == Decimal("220")
        assert row[15] == Decimal("30")  # bruto ANTES da conversao
        assert row[16] == "kWh/mes"

    def test_observation_sql_persists_provenance(self) -> None:
        for column in (
            "is_generic",
            "voltage_raw",
            "voltage_kind",
            "voltage_min_v",
            "voltage_max_v",
            "raw_energy_value",
            "raw_energy_unit",
        ):
            assert column in _INSERT_OBSERVATION_SQL

    def test_conflict_target_is_natural_key(self) -> None:
        # Spec 3.4: duplicata de origem e ignorada pela chave natural.
        assert "ON CONFLICT (source, external_id) DO NOTHING" in (
            _INSERT_OBSERVATION_SQL
        )

    def test_return_zero_for_empty_batch(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        assert insert_source_observations(pool, []) == 0
        cursor.executemany.assert_not_called()

    def test_translate_errors_to_persistence_error(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        cursor.executemany.side_effect = RuntimeError("db down")

        with pytest.raises(PersistenceError):
            insert_source_observations(pool, [make_product(source_id="A-1")])


# ------------------------------------------------------------------ #
# insert_aggregates — aggregate_reference (insert-only)
# ------------------------------------------------------------------ #


class TestInsertAggregates:
    def test_should_write_params_sorted_by_uuid(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        records = [
            AggregateRecord(
                source="IEA",
                country="Japan",
                ref_year=2020,
                metric="stock",
                value=Decimal(5),
                unit="thousands",
                appliance="televisions",
            ),
            AggregateRecord(
                source="IEA",
                country="France",
                ref_year=2019,
                metric="stock",
                value=Decimal(100),
                unit="thousands",
                appliance="refrigerators",
            ),
        ]

        written = insert_aggregates(pool, records)

        assert written == 2
        params = cursor.executemany.call_args.args[1]
        assert params[0][0] < params[1][0]  # ordenado por UUID asc

    def test_should_return_zero_for_empty_batch(self) -> None:
        pool, _conn, cursor = make_fake_pool()

        assert insert_aggregates(pool, []) == 0
        cursor.executemany.assert_not_called()

    def test_should_translate_errors_to_persistence_error(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        cursor.executemany.side_effect = RuntimeError("db down")
        records = [
            AggregateRecord(
                source="IEA",
                country="France",
                ref_year=2019,
                metric="stock",
                value=Decimal(100),
                unit="thousands",
            )
        ]

        with pytest.raises(PersistenceError):
            insert_aggregates(pool, records)
