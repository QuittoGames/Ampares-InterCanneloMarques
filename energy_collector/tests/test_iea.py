"""Testes unitarios do adapter IEA — agregados anonimos (PR 5, D6=A).

Tudo in-memory (CSV sintetico): nenhum teste toca rede, disco ou banco.

Cobre:

* Protocolo — conformidade ``SourceClient``/``SourceAdapter`` e
  ``source_type == "aggregate"`` (rota para ``aggregate_reference``).
* Identidade — uuid5 sobre ``IEA|{pais}|{ano}|{metrica}|{aparelho}``;
  deterministico; sem colisao entre paises/metricas/aparelhos.
* Normalizacao — retorna ``AggregateRecord`` (NAO ``Product``);
  descarte sem invencao (pais/ano/metrica/valor obrigatorios); ano
  valido (1900+); valor Decimal; unidade preservada.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

import pytest

from collector.models import AggregateRecord
from collector.sources.iea import (
    DATASET_ID,
    SOURCE_TYPE,
    IeaAdapter,
    IeaClient,
)
from collector.sources.protocol import SourceAdapter, SourceClient

CSV_OK = (
    "country,year,metric,appliance,value,unit\n"
    "France,2019,stock,refrigerators,1000000,thousands\n"
    "Japan,2020,energy_per_stock,televisions,120.5,PJ\n"
    "Brazil,2021,diffusion,air conditioners,0.75,ratio\n"
)
CSV_NO_VALUE = "country,year,metric,value\nFrance,2019,stock,\n"
CSV_BAD_YEAR = "country,year,metric,value\nFrance,19xx,stock,100\n"
CSV_NO_COUNTRY = "country,year,metric,value\n,2019,stock,100\n"


# ------------------------------------------------------------------ #
# Helpers
# ------------------------------------------------------------------ #


def make_client(content: str) -> IeaClient:
    return IeaClient(csv_content=content)


def normalize_row(content: str, index: int = 0) -> Any:
    adapter = IeaAdapter(client=make_client(content))
    pages = list(adapter.iter_raw_records(dataset_id=DATASET_ID, page_size=10))
    records = pages[0][1]
    return adapter.normalize(records[index], dataset_id=DATASET_ID, category="")


# ------------------------------------------------------------------ #
# Protocolo (DIP)
# ------------------------------------------------------------------ #


class TestProtocolConformance:
    def test_client_conforms_to_source_client(self) -> None:
        assert isinstance(make_client(CSV_OK), SourceClient)

    def test_adapter_conforms_to_source_adapter(self) -> None:
        assert isinstance(IeaAdapter(), SourceAdapter)

    def test_client_requires_content_or_path(self) -> None:
        with pytest.raises(ValueError, match="csv_content ou csv_path"):
            IeaClient()

    def test_source_type_is_aggregate(self) -> None:
        """D6=A: agregados NAO sao produtos — rota agregada."""
        assert SOURCE_TYPE == "aggregate"
        assert IeaAdapter().source_type == "aggregate"

    def test_discover_returns_household_appliances(self) -> None:
        datasets = make_client(CSV_OK).discover()
        assert datasets == [(DATASET_ID, "IEA Household Appliances Database")]


# ------------------------------------------------------------------ #
# Identidade deterministica
# ------------------------------------------------------------------ #


class TestDeterministicIdentity:
    def test_record_id_stable_for_same_combination(self) -> None:
        r1 = normalize_row(CSV_OK)
        r2 = normalize_row(CSV_OK)
        assert r1 is not None and r2 is not None
        assert r1.record_id() == r2.record_id()

    def test_record_id_differs_between_countries(self) -> None:
        r1 = normalize_row(CSV_OK, index=0)  # France stock refrigerators
        r2 = normalize_row(CSV_OK, index=1)  # Japan energy TVs
        assert r1 is not None and r2 is not None
        assert r1.record_id() != r2.record_id()

    def test_record_id_differs_between_years(self) -> None:
        """Mesma combinacao, anos diferentes => UUIDs distintos."""
        csv_two_years = (
            "country,year,metric,appliance,value,unit\n"
            "France,2019,stock,refrigerators,100,thousands\n"
            "France,2020,stock,refrigerators,110,thousands\n"
        )
        r1 = normalize_row(csv_two_years, index=0)
        r2 = normalize_row(csv_two_years, index=1)
        assert r1 is not None and r2 is not None
        assert r1.record_id() != r2.record_id()


# ------------------------------------------------------------------ #
# Normalizacao
# ------------------------------------------------------------------ #


class TestNormalize:
    def test_returns_aggregate_record_not_product(self) -> None:
        record = normalize_row(CSV_OK)
        assert isinstance(record, AggregateRecord)
        from collector.models import Product

        assert not isinstance(record, Product)

    def test_fields_mapped(self) -> None:
        record = normalize_row(CSV_OK)
        assert record is not None
        assert record.source == "IEA"
        assert record.country == "France"
        assert record.ref_year == 2019
        assert record.metric == "stock"
        assert record.appliance == "refrigerators"
        assert record.value == Decimal(1000000)
        assert record.unit == "thousands"

    def test_decimal_value_with_fraction(self) -> None:
        record = normalize_row(CSV_OK, index=1)
        assert record is not None
        assert record.value == Decimal("120.5")
        assert record.unit == "PJ"

    def test_discards_without_value(self) -> None:
        assert normalize_row(CSV_NO_VALUE) is None

    def test_discards_invalid_year(self) -> None:
        assert normalize_row(CSV_BAD_YEAR) is None

    def test_discards_without_country(self) -> None:
        assert normalize_row(CSV_NO_COUNTRY) is None

    def test_appliance_optional(self) -> None:
        record = normalize_row("country,year,metric,value\nFrance,2019,stock,100\n")
        assert record is not None
        assert record.appliance is None
        assert record.unit == ""


# ------------------------------------------------------------------ #
# Transporte/paginacao
# ------------------------------------------------------------------ #


class TestTransport:
    def test_fetch_page_slices(self) -> None:
        client = make_client(CSV_OK)
        assert client.fetch_page(DATASET_ID, limit=1, offset=1) == [
            {
                "country": "Japan",
                "year": "2020",
                "metric": "energy_per_stock",
                "appliance": "televisions",
                "value": "120.5",
                "unit": "PJ",
            }
        ]

    def test_count(self) -> None:
        assert make_client(CSV_OK).count(DATASET_ID) == 3

    def test_iter_respects_limit(self) -> None:
        adapter = IeaAdapter(client=make_client(CSV_OK))
        pages = list(
            adapter.iter_raw_records(dataset_id=DATASET_ID, page_size=1, limit=2)
        )
        assert sum(len(recs) for _o, recs in pages) == 2

    def test_iter_requires_client(self) -> None:
        with pytest.raises(RuntimeError, match="IeaClient"):
            next(IeaAdapter().iter_raw_records(dataset_id=DATASET_ID, page_size=10))

    def test_source_pk_combines_dimensions(self) -> None:
        client = make_client(CSV_OK)
        adapter = IeaAdapter(client=client)
        pages = list(adapter.iter_raw_records(dataset_id=DATASET_ID, page_size=10))
        record = pages[0][1][0]
        assert record.get("source_pk") == "France|2019|stock|refrigerators"
