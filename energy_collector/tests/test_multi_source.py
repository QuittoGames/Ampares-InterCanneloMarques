"""Testes do MultiSourceCollectionService (PR 6, D8=A — Strangler Fig).

Valida o ORQUESTRADOR DIP: consome qualquer ``SourceAdapter`` e roteia
a persistencia por ``source_type`` — ``individual_product`` →
``product`` (+ ENCE), ``aggregate`` → ``aggregate_reference``.

Estrategia: pool falso (``make_fake_pool``) + adapters REAIS
(WattSimple/INMETRO/IEA com CSV in-memory). Nenhuma rede, nenhum banco.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any
from unittest.mock import MagicMock

import pytest

from collector.models import AggregateRecord
from collector.services.multi_source import MultiSourceCollectionService
from collector.sources.iea import DATASET_ID as IEA_DATASET
from collector.sources.iea import IeaAdapter, IeaClient
from collector.sources.inmetro import DATASET_ID as INMETRO_DATASET
from collector.sources.inmetro import InmetroAdapter, InmetroClient
from collector.sources.wattsimple import SOURCE_CODE as WS_CODE
from collector.sources.wattsimple import WattSimpleAdapter, WattSimpleClient

from .conftest import make_fake_pool

# ------------------------------------------------------------------ #
# Helpers
# ------------------------------------------------------------------ #

WS_CSV = "name,watts\nGeladeira,150\nMicro-ondas,1200\n"
INMETRO_CSV = (
    "marca,modelo,categoria,classe,kwh_mes\n"
    "Electrolux,DC50,1,A,30\n"
    "Brastemp,BRK47,5,A++,38\n"
)
IEA_CSV = (
    "country,year,metric,appliance,value,unit\n"
    "France,2019,stock,refrigerators,1000000,thousands\n"
    "Japan,2020,energy_per_stock,televisions,120.5,PJ\n"
)

UPSERT_PRODUCT_SQL_SNIPPET = "INSERT INTO product"
UPSERT_LABEL_SQL_SNIPPET = "INSERT INTO energy_label_class"
UPSERT_AGGREGATE_SQL_SNIPPET = "INSERT INTO aggregate_reference"


def executed_sqls(conn: MagicMock) -> list[str]:
    """SQLs passados a cursor.executemany (primeiro arg)."""
    return [c.args[0] for c in _executemany_calls(conn)]


def _executemany_calls(conn: MagicMock) -> list[Any]:
    cursor = conn.cursor.return_value.__enter__.return_value
    return list(cursor.executemany.call_args_list)


def executemany_rows(conn: MagicMock) -> list[list[tuple]]:
    """Parametros de cada executemany (lista de lotes)."""
    cursor = conn.cursor.return_value.__enter__.return_value
    return [c.args[1] for c in cursor.executemany.call_args_list]


# ------------------------------------------------------------------ #
# Produtos individuais (WattSimple — rota product + is_generic)
# ------------------------------------------------------------------ #


class TestCollectWattSimple:
    def test_routes_to_product_table(self) -> None:
        pool, conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)
        adapter = WattSimpleAdapter(client=WattSimpleClient(csv_content=WS_CSV))

        rep = service.collect(adapter, dataset_id=WS_CODE, category="wattsimple")

        assert rep.status == "ok"
        assert rep.received == 2
        assert rep.inserted == 2
        # So a rota product — nunca aggregate_reference.
        assert UPSERT_PRODUCT_SQL_SNIPPET in executed_sqls(conn)[0]
        assert all(
            UPSERT_AGGREGATE_SQL_SNIPPET not in sql for sql in executed_sqls(conn)
        )

    def test_writes_is_generic_true(self) -> None:
        pool, conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)
        adapter = WattSimpleAdapter(client=WattSimpleClient(csv_content=WS_CSV))

        service.collect(adapter, dataset_id=WS_CODE, category="wattsimple")

        rows = executemany_rows(conn)[0]
        assert all(row[-1] is True for row in rows)  # is_generic = True

    def test_limit_respects_smoke_test(self) -> None:
        pool, _conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)
        adapter = WattSimpleAdapter(client=WattSimpleClient(csv_content=WS_CSV))

        rep = service.collect(
            adapter, dataset_id=WS_CODE, category="wattsimple", limit=1
        )

        assert rep.received == 1
        assert rep.inserted == 1


# ------------------------------------------------------------------ #
# Produtos brandados + ENCE (INMETRO — rota product + energy_label_class)
# ------------------------------------------------------------------ #


class TestCollectInmetro:
    def test_routes_to_product_and_label_class(self) -> None:
        pool, conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)
        adapter = InmetroAdapter(client=InmetroClient(csv_content=INMETRO_CSV))

        rep = service.collect(adapter, dataset_id=INMETRO_DATASET, category="inmetro")

        assert rep.status == "ok"
        sqls = executed_sqls(conn)
        assert any(UPSERT_PRODUCT_SQL_SNIPPET in sql for sql in sqls), (
            "deve gravar em product"
        )
        assert any(UPSERT_LABEL_SQL_SNIPPET in sql for sql in sqls), (
            "deve gravar ENCE em energy_label_class"
        )

    def test_label_class_rows_written(self) -> None:
        pool, conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)
        adapter = InmetroAdapter(client=InmetroClient(csv_content=INMETRO_CSV))

        service.collect(adapter, dataset_id=INMETRO_DATASET, category="inmetro")

        label_rows = executemany_rows(conn)[1]  # product primeiro, ENCE depois
        assert len(label_rows) == 2
        assert {row[1] for row in label_rows} == {"A", "A++"}


# ------------------------------------------------------------------ #
# Agregados anonimos (IEA — rota aggregate_reference)
# ------------------------------------------------------------------ #


class TestCollectIea:
    def test_routes_to_aggregate_reference_only(self) -> None:
        pool, conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)
        adapter = IeaAdapter(client=IeaClient(csv_content=IEA_CSV))

        rep = service.collect(adapter, dataset_id=IEA_DATASET, category="iea")

        assert rep.status == "ok"
        assert rep.received == 2
        assert rep.inserted == 2  # upsert_aggregates devolve gravados
        sqls = executed_sqls(conn)
        assert any(UPSERT_AGGREGATE_SQL_SNIPPET in sql for sql in sqls)
        assert all(UPSERT_PRODUCT_SQL_SNIPPET not in sql for sql in sqls), (
            "agregado NUNCA vai para product"
        )


# ------------------------------------------------------------------ #
# Descartes e falhas isoladas
# ------------------------------------------------------------------ #


class TestDiscardsAndFailures:
    def test_discarded_rows_never_reach_db(self) -> None:
        pool, conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)
        bad_csv = "name,watts\n,150\nLiquidificador,\n"  # sem nome / sem watts
        adapter = WattSimpleAdapter(client=WattSimpleClient(csv_content=bad_csv))

        rep = service.collect(adapter, dataset_id=WS_CODE, category="wattsimple")

        assert rep.received == 2
        assert rep.discarded == 2
        assert rep.inserted == 0
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.executemany.assert_not_called()

    def test_db_failure_marks_dataset_failed(self) -> None:
        pool, _conn, cursor = make_fake_pool()
        cursor.executemany.side_effect = RuntimeError("db down")
        service = MultiSourceCollectionService(pool=pool)
        adapter = WattSimpleAdapter(client=WattSimpleClient(csv_content=WS_CSV))

        rep = service.collect(adapter, dataset_id=WS_CODE, category="wattsimple")

        assert rep.status == "failed"
        assert rep.inserted == 0

    def test_unexpected_adapter_failure_isolated(self) -> None:
        pool, _conn, _cur = make_fake_pool()
        service = MultiSourceCollectionService(pool=pool)

        class ExplodingAdapter:
            code = "X"
            source_type = "individual_product"

            def iter_raw_records(self, **_kw: Any) -> Any:
                raise RuntimeError("boom")

            def normalize(self, *_a: Any, **_kw: Any) -> Any:  # pragma: no cover
                raise AssertionError("nunca chamado")

        rep = service.collect(ExplodingAdapter(), dataset_id="x", category="x")

        assert rep.status == "failed"

    def test_unknown_normalize_result_discarded(self) -> None:
        pool, _conn, _cur = make_fake_pool()
        service = MultiSourceCollectionService(pool=pool)

        class WeirdAdapter:
            code = "W"
            source_type = "individual_product"

            def iter_raw_records(self, **_kw: Any) -> Any:
                yield 0, [{"source_pk": "w1", "raw": {}}]

            def normalize(self, *_a: Any, **_kw: Any) -> Any:
                return object()  # tipo desconhecido

        rep = service.collect(WeirdAdapter(), dataset_id="w", category="w")

        assert rep.discarded == 1
        assert rep.inserted == 0


# ------------------------------------------------------------------ #
# Paridade de relatorio (legado → multi-source)
# ------------------------------------------------------------------ #


class TestReportParity:
    def test_report_shape_matches_legacy_contract(self) -> None:
        pool, _conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)
        adapter = WattSimpleAdapter(client=WattSimpleClient(csv_content=WS_CSV))

        rep = service.collect(adapter, dataset_id=WS_CODE, category="wattsimple")

        # Mesmos campos do CategoryReport do legado (FR-011).
        for attr in (
            "category",
            "dataset_id",
            "received",
            "inserted",
            "updated",
            "discarded",
            "status",
        ):
            assert hasattr(rep, attr)


# ------------------------------------------------------------------ #
# Roteamento defensivo por tipo (isinstance)
# ------------------------------------------------------------------ #


class TestDefensiveRouting:
    def test_aggregate_from_individual_source_is_routed_by_type(self) -> None:
        """Se uma fonte 'individual' devolver AggregateRecord, o dado
        ainda persiste como agregado (roteamento defensivo por tipo)."""
        pool, conn, _cur = make_fake_pool(existing=0)
        service = MultiSourceCollectionService(pool=pool)

        class MixedAdapter:
            code = "M"
            source_type = "individual_product"

            def iter_raw_records(self, **_kw: Any) -> Any:
                yield 0, [{"source_pk": "m1", "raw": {}}]

            def normalize(self, *_a: Any, **_kw: Any) -> Any:
                return AggregateRecord(
                    source="M",
                    country="France",
                    ref_year=2019,
                    metric="stock",
                    value=Decimal(1),
                    unit="thousands",
                )

        service.collect(MixedAdapter(), dataset_id="m", category="m")

        sqls = executed_sqls(conn)
        assert any(UPSERT_AGGREGATE_SQL_SNIPPET in sql for sql in sqls)


# ------------------------------------------------------------------ #
# collect_all — adapters sem discover_datasets
# ------------------------------------------------------------------ #


class TestCollectAll:
    def test_requires_discover_datasets(self) -> None:
        pool, _conn, _cur = make_fake_pool()
        service = MultiSourceCollectionService(pool=pool)

        with pytest.raises(TypeError, match="discover_datasets"):
            service.collect_all(WattSimpleAdapter())
