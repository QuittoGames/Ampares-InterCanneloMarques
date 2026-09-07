"""Testes unitarios do adapter WattSimple (PR 3 — produtos genericos).

Tudo in-memory (CSV sintetico): nenhum teste toca rede, disco ou banco.

Cobre:

* Protocolo — ``WattSimpleClient``/``WattSimpleAdapter`` conformes a
  ``SourceClient``/``SourceAdapter`` via duck-typing.
* Identidade — ``"WATTSIMPLE|{nome}"`` via uuid5; deterministico,
  sem colisao com o namespace ENERGY STAR, sensivel a NFKC/casefold.
* Normalizacao — ``is_generic=True`` sempre; ``brand``/``model`` None
  (generico); descarte SEM invencao de valores; taxonomia global
  reaproveitada (mesma categoria do app para o mesmo aparelho).
* Transporte — paginacao por ``fetch_page`` (limit/offset) e
  ``iter_raw_records`` (fatia em paginas fixas, respeita ``limit``).
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

import pytest

from collector.sources.protocol import RawRecord, SourceAdapter, SourceClient
from collector.sources.wattsimple import (
    SOURCE_CODE,
    WattSimpleAdapter,
    WattSimpleClient,
)

CSV_SIMPLE = "name,watts\nGeladeira,150\nMicro-ondas,1200\n"
CSV_ANNUAL = "name,avg_power_w,annual_energy_kwh\nTV LED,100,180\n"
CSV_EMPTY_POWER = "name,watts\nLiquidificador,\n"
CSV_NO_NAME = "name,watts\n,300\n"


# ------------------------------------------------------------------ #
# Helpers
# ------------------------------------------------------------------ #


def make_client(content: str) -> WattSimpleClient:
    return WattSimpleClient(csv_content=content)


def first_normalized(content: str) -> Any:
    client = make_client(content)
    adapter = WattSimpleAdapter(client=client)
    (_offset, records), _ = _consume_first(adapter)
    assert records, "nenhum registro bruto produzido"
    return adapter.normalize(records[0], dataset_id=SOURCE_CODE, category="")


def _consume_first(
    adapter: WattSimpleAdapter,
) -> tuple[tuple[int, list[RawRecord]], int]:
    pages = list(adapter.iter_raw_records(dataset_id=SOURCE_CODE, page_size=10))
    assert pages, "nenhuma pagina produzida"
    return pages[0], len(pages)


# ------------------------------------------------------------------ #
# Protocolo (DIP)
# ------------------------------------------------------------------ #


class TestProtocolConformance:
    def test_client_conforms_to_source_client(self) -> None:
        assert isinstance(make_client(CSV_SIMPLE), SourceClient)

    def test_adapter_conforms_to_source_adapter(self) -> None:
        assert isinstance(WattSimpleAdapter(), SourceAdapter)

    def test_client_requires_content_or_path(self) -> None:
        with pytest.raises(ValueError, match="csv_content ou csv_path"):
            WattSimpleClient()

    def test_discover_returns_single_dataset(self) -> None:
        client = make_client(CSV_SIMPLE)
        datasets = client.discover()
        assert len(datasets) == 1
        assert datasets[0][0] == SOURCE_CODE


# ------------------------------------------------------------------ #
# Identidade deterministica
# ------------------------------------------------------------------ #


class TestDeterministicIdentity:
    def test_uuid_is_stable_for_same_name(self) -> None:
        client = make_client(CSV_SIMPLE)
        adapter = WattSimpleAdapter(client=client)

        pages = list(adapter.iter_raw_records(dataset_id=SOURCE_CODE, page_size=10))
        records = pages[0][1]
        p1 = adapter.normalize(records[0], dataset_id=SOURCE_CODE, category="")
        p2 = adapter.normalize(records[0], dataset_id=SOURCE_CODE, category="")

        assert p1 is not None and p2 is not None
        assert p1.product_id() == p2.product_id()

    def test_uuid_differs_from_energy_star_namespace(self) -> None:
        """Mesmo source_id em fontes diferentes => UUIDs distintos."""
        product = first_normalized(CSV_SIMPLE)
        assert product is not None
        # Simula produto ENERGY STAR com o MESMO source_id (nome).
        from tests.conftest import make_product

        es_product = make_product(source_id=product.source_id or "Geladeira")
        assert product.product_id() != es_product.product_id()

    def test_dedup_key_uses_wattsimple_prefix_and_name(self) -> None:
        product = first_normalized(CSV_SIMPLE)
        assert product is not None
        assert product.dedup_key() == "WATTSIMPLE|geladeira"


# ------------------------------------------------------------------ #
# Normalizacao
# ------------------------------------------------------------------ #


class TestNormalize:
    def test_sets_is_generic_true(self) -> None:
        product = first_normalized(CSV_SIMPLE)
        assert product is not None
        assert product.is_generic is True

    def test_source_is_wattsimple(self) -> None:
        product = first_normalized(CSV_SIMPLE)
        assert product is not None
        assert product.source == "WATTSIMPLE"

    def test_brand_and_model_are_none(self) -> None:
        product = first_normalized(CSV_SIMPLE)
        assert product is not None
        assert product.brand is None
        assert product.model is None

    def test_power_from_watts_column(self) -> None:
        product = first_normalized(CSV_SIMPLE)
        assert product is not None
        assert product.avg_power_w == Decimal("150.0")

    def test_power_from_avg_power_w_column(self) -> None:
        product = first_normalized(CSV_ANNUAL)
        assert product is not None
        assert product.avg_power_w == Decimal("100.0")

    def test_annual_from_alternative_column(self) -> None:
        product = first_normalized(CSV_ANNUAL)
        assert product is not None
        assert product.annual_energy_kwh == Decimal("180.0")

    def test_discards_row_without_power_and_annual(self) -> None:
        product = first_normalized(CSV_EMPTY_POWER)
        assert product is None

    def test_discards_row_without_name(self) -> None:
        product = first_normalized(CSV_NO_NAME)
        assert product is None

    def test_uses_global_taxonomy_for_category(self) -> None:
        product = first_normalized(CSV_SIMPLE)
        assert product is not None
        # Geladeira mapeia para Eletrodomesticos na taxonomia global.
        assert product.category == "Eletrodomésticos"
        assert product.subcategory == "Geladeira"

    def test_source_id_is_the_name(self) -> None:
        product = first_normalized(CSV_SIMPLE)
        assert product is not None
        assert product.source_id == "Geladeira"


# ------------------------------------------------------------------ #
# Transporte/paginacao
# ------------------------------------------------------------------ #


class TestTransport:
    def test_fetch_page_slices_by_limit_offset(self) -> None:
        client = make_client(CSV_SIMPLE)
        assert client.fetch_page(SOURCE_CODE, limit=1, offset=0) == [
            {"name": "Geladeira", "watts": "150"}
        ]
        assert client.fetch_page(SOURCE_CODE, limit=1, offset=1) == [
            {"name": "Micro-ondas", "watts": "1200"}
        ]

    def test_fetch_page_out_of_range_returns_empty(self) -> None:
        client = make_client(CSV_SIMPLE)
        assert client.fetch_page(SOURCE_CODE, limit=5, offset=99) == []

    def test_count_returns_row_count(self) -> None:
        assert make_client(CSV_SIMPLE).count(SOURCE_CODE) == 2

    def test_iter_raw_records_respects_limit(self) -> None:
        adapter = WattSimpleAdapter(client=make_client(CSV_SIMPLE))
        pages = list(
            adapter.iter_raw_records(dataset_id=SOURCE_CODE, page_size=1, limit=1)
        )
        total_records = sum(len(records) for _offset, records in pages)
        assert total_records == 1

    def test_iter_raw_records_slices_in_pages(self) -> None:
        adapter = WattSimpleAdapter(client=make_client(CSV_SIMPLE))
        pages = list(adapter.iter_raw_records(dataset_id=SOURCE_CODE, page_size=1))
        assert len(pages) == 2
        assert all(len(records) == 1 for _offset, records in pages)

    def test_iter_raw_records_offsets_are_consecutive(self) -> None:
        adapter = WattSimpleAdapter(client=make_client(CSV_SIMPLE))
        offsets = [
            offset
            for offset, _records in adapter.iter_raw_records(
                dataset_id=SOURCE_CODE, page_size=1
            )
        ]
        assert offsets == [0, 1]

    def test_iter_raw_records_requires_client(self) -> None:
        adapter = WattSimpleAdapter()
        with pytest.raises(RuntimeError, match="WattSimpleClient"):
            next(adapter.iter_raw_records(dataset_id=SOURCE_CODE, page_size=10))

    def test_headers_are_lowercased_and_stripped(self) -> None:
        client = make_client("Name , Watts \nGeladeira,150\n")
        rows = client.fetch_page(SOURCE_CODE, limit=10, offset=0)
        assert rows == [{"name": "Geladeira", "watts": "150"}]
