"""Testes unitarios de ``collector.database`` (PR 2 — migracoes multi-fonte).

Tudo com pool falso (``MagicMock``): nenhum teste toca rede ou banco reais.

Cobre:

* ``ensure_table`` — executa TODAS as migracoes multi-fonte (coluna
  ``is_generic`` + ``energy_specification`` + 4 tabelas auxiliares),
  cada uma como statement individual (psycopg3 nao aceita multiplos
  statements em um unico ``execute``).
* ``upsert_batch`` — o INSERT agora inclui ``is_generic`` (10a coluna)
  e o ``ON CONFLICT`` o atualiza; pre-count e ordenacao por UUID intactos.
* ``UpsertStats`` — contrato do relatorio inserted/updated.
"""

from __future__ import annotations

from decimal import Decimal

import pytest

from collector.database import (
    _ALTER_IS_GENERIC_SQL,
    _CREATE_ENERGY_LABEL_CLASS_SQL,
    _CREATE_ENERGY_RAW_MEASUREMENT_SQL,
    _CREATE_ENERGY_SPEC_SQL,
    _CREATE_SOURCE_METADATA_SQL,
    _CREATE_SOURCE_PRODUCT_SQL,
    _CREATE_SQL,
    _UPSERT_SQL,
    UpsertStats,
    ensure_table,
    upsert_aggregates,
    upsert_batch,
    upsert_label_classes,
)
from collector.exceptions import PersistenceError
from collector.models import AggregateRecord

from .conftest import make_fake_pool, make_product

# ------------------------------------------------------------------ #
# ensure_table — migracoes multi-fonte (PR 2)
# ------------------------------------------------------------------ #


class TestEnsureTableMigrations:
    def test_should_execute_all_multisource_statements(self) -> None:
        pool, conn, _cursor = make_fake_pool()

        ensure_table(pool)

        executed = [c.args[0] for c in conn.execute.call_args_list]
        # Ordem obrigatoria: product primeiro (FKs dependem dela),
        # depois colunas, depois tabelas auxiliares.
        assert _ALTER_IS_GENERIC_SQL in executed
        assert _CREATE_ENERGY_SPEC_SQL in executed
        assert _CREATE_SOURCE_PRODUCT_SQL in executed
        assert _CREATE_ENERGY_LABEL_CLASS_SQL in executed
        assert _CREATE_ENERGY_RAW_MEASUREMENT_SQL in executed
        assert _CREATE_SOURCE_METADATA_SQL in executed

    def test_should_execute_product_create_before_auxiliary_tables(self) -> None:
        pool, conn, _cursor = make_fake_pool()

        ensure_table(pool)

        executed = [c.args[0] for c in conn.execute.call_args_list]
        # _CREATE_SQL cria 'product' primeiro (FKs das auxiliares dependem).
        create_pos = executed.index(_CREATE_SQL)
        aux_pos = executed.index(_CREATE_SOURCE_PRODUCT_SQL)
        assert create_pos < aux_pos

    def test_should_wrap_in_transaction(self) -> None:
        pool, conn, _cursor = make_fake_pool()

        ensure_table(pool)

        conn.transaction.assert_called()

    def test_should_translate_failures_to_persistence_error(self) -> None:
        pool, conn, _cursor = make_fake_pool()
        conn.execute.side_effect = RuntimeError("boom")

        with pytest.raises(PersistenceError, match="product"):
            ensure_table(pool)


# ------------------------------------------------------------------ #
# upsert_batch — coluna is_generic (PR 2)
# ------------------------------------------------------------------ #


class TestUpsertBatchIsGeneric:
    def test_should_include_is_generic_in_params(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        branded = make_product(source_id="A-1", is_generic=False)
        generic = make_product(source_id="A-2", is_generic=True)

        upsert_batch(pool, [branded, generic])

        # executemany recebe [(id, name, brand, model, cat, subcat,
        # power, annual, standby, is_generic), ...] ordenado por UUID.
        assert cursor.executemany.called
        params = cursor.executemany.call_args.args[1]
        assert len(params) == 2
        generic_flag = {row[-1] for row in params}
        assert generic_flag == {False, True}

    def test_should_map_param_row_to_matching_product(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        branded = make_product(source_id="A-1", is_generic=False)
        generic = make_product(source_id="A-2", is_generic=True)

        upsert_batch(pool, [branded, generic])

        params = cursor.executemany.call_args.args[1]
        # Cada linha casa com o UUID do seu produto (ordem por UUID preservada).
        by_id = {str(p.product_id()): p for p in (branded, generic)}
        for row in params:
            product = by_id[row[0]]
            assert row[-1] is product.is_generic

    def test_should_update_is_generic_on_conflict(self) -> None:
        # O SQL de upsert precisa citar is_generic no ON CONFLICT.
        assert "is_generic" in _UPSERT_SQL
        assert _UPSERT_SQL.count("is_generic") >= 2  # INSERT + UPDATE

    def test_should_sort_by_uuid_before_write(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        p1 = make_product(source_id="ZZZ-1")
        p2 = make_product(source_id="AAA-2")

        upsert_batch(pool, [p1, p2])

        params = cursor.executemany.call_args.args[1]
        assert params[0][0] < params[1][0]  # ids ordenados asc

    def test_should_return_empty_stats_for_empty_batch(self) -> None:
        pool, _conn, _cursor = make_fake_pool()

        stats = upsert_batch(pool, [])

        assert stats.inserted == 0
        assert stats.updated == 0

    def test_should_count_inserted_and_updated(self) -> None:
        pool, _conn, _cursor = make_fake_pool(existing=1)
        products = [
            make_product(source_id="A-1"),
            make_product(source_id="A-2"),
        ]

        stats = upsert_batch(pool, products)

        assert stats.inserted == 1
        assert stats.updated == 1

    def test_should_translate_db_error_to_persistence_error(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        cursor.executemany.side_effect = RuntimeError("db down")

        with pytest.raises(PersistenceError):
            upsert_batch(pool, [make_product()])


# ------------------------------------------------------------------ #
# Contrato UpsertStats
# ------------------------------------------------------------------ #


class TestUpsertStatsContract:
    def test_should_default_to_zero(self) -> None:
        stats = UpsertStats()
        assert stats.inserted == 0
        assert stats.updated == 0

    def test_should_hold_values(self) -> None:
        stats = UpsertStats(inserted=3, updated=5)
        assert stats.inserted == 3
        assert stats.updated == 5


# ------------------------------------------------------------------ #
# Regressao: Decimal params intactos
# ------------------------------------------------------------------ #


class TestUpsertDecimalRegression:
    def test_should_pass_decimals_untouched(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        products = [
            make_product(
                source_id="A-1",
                power=Decimal("150.0"),
                annual=Decimal("420.00"),
            )
        ]

        upsert_batch(pool, products)

        params = cursor.executemany.call_args.args[1]
        row = params[0]
        assert row[6] == Decimal("150.0")
        assert row[7] == Decimal("420.00")


# ------------------------------------------------------------------ #
# upsert_label_classes — tabela auxiliar energy_label_class (PR 4)
# ------------------------------------------------------------------ #


class TestUpsertLabelClasses:
    def test_should_write_only_labeled_products(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        products = [
            make_product(source_id="A-1", label_class="A"),
            make_product(source_id="A-2", label_class=None),  # ignorado
        ]

        written = upsert_label_classes(pool, products)

        assert written == 1
        params = cursor.executemany.call_args.args[1]
        assert len(params) == 1
        assert params[0][1] == "A"

    def test_should_return_zero_for_no_labels(self) -> None:
        pool, _conn, cursor = make_fake_pool()

        written = upsert_label_classes(pool, [make_product()])

        assert written == 0
        cursor.executemany.assert_not_called()

    def test_should_return_zero_for_empty_batch(self) -> None:
        pool, _conn, _cursor = make_fake_pool()

        assert upsert_label_classes(pool, []) == 0

    def test_should_sort_by_uuid_before_write(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        p1 = make_product(source_id="ZZZ-1", label_class="B")
        p2 = make_product(source_id="AAA-2", label_class="A")

        upsert_label_classes(pool, [p1, p2])

        params = cursor.executemany.call_args.args[1]
        assert params[0][0] < params[1][0]

    def test_should_use_upsert_with_updated_at(self) -> None:
        # ON CONFLICT atualiza a classe e o timestamp (re-classificacao).
        from collector.database import _LABEL_CLASS_UPSERT_SQL

        assert "ON CONFLICT (id) DO UPDATE" in _LABEL_CLASS_UPSERT_SQL
        assert "updated_at" in _LABEL_CLASS_UPSERT_SQL

    def test_should_translate_errors_to_persistence_error(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        cursor.executemany.side_effect = RuntimeError("db down")

        with pytest.raises(PersistenceError):
            upsert_label_classes(pool, [make_product(label_class="A")])


# ------------------------------------------------------------------ #
# upsert_aggregates — tabela aggregate_reference (PR 5, D6=A)
# ------------------------------------------------------------------ #


class TestUpsertAggregates:
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

        written = upsert_aggregates(pool, records)

        assert written == 2
        params = cursor.executemany.call_args.args[1]
        assert params[0][0] < params[1][0]  # ordenado por UUID asc

    def test_should_return_zero_for_empty_batch(self) -> None:
        pool, _conn, cursor = make_fake_pool()

        assert upsert_aggregates(pool, []) == 0
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
            upsert_aggregates(pool, records)

    def test_ensure_table_includes_aggregate_reference(self) -> None:
        from collector.database import (
            _CREATE_AGGREGATE_REFERENCE_SQL,
            _CREATE_SQL,
        )

        pool, conn, _cursor = make_fake_pool()
        ensure_table(pool)

        executed = [c.args[0] for c in conn.execute.call_args_list]
        assert _CREATE_AGGREGATE_REFERENCE_SQL in executed
        # product primeiro (mesmo sem FK, ordem logica do schema).
        assert executed.index(_CREATE_SQL) < executed.index(
            _CREATE_AGGREGATE_REFERENCE_SQL
        )
