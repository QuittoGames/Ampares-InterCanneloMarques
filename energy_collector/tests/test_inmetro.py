"""Testes unitarios do adapter INMETRO/PBE refrigeradores (PR 4, D5=A).

Tudo in-memory (CSV sintetico): nenhum teste toca rede, disco ou banco.

Cobre:

* Protocolo — conformidade ``SourceClient``/``SourceAdapter``.
* Identidade — ``"INMETRO|{marca}|{modelo}"`` via uuid5; deterministico;
  isolado do namespace ENERGY STAR (D7=A: sem cruzamento).
* Normalizacao — produto brandado (marca/modelo obrigatorios);
  ``label_class`` ENCE validado (A..G, A+, A++); consumo kWh/mes ->
  kWh/ano (x12); subcategoria derivada da categoria oficial (1-6,
  Portaria 736/2024); descarte sem invencao de valores.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

import pytest

from collector.sources.inmetro import (
    DATASET_ID,
    InmetroAdapter,
    InmetroClient,
)
from collector.sources.protocol import SourceAdapter, SourceClient

CSV_OK = (
    "marca,modelo,categoria,classe,kwh_mes\n"
    "Electrolux,DC50,1,A,30\n"
    "Brastemp,BRK47,5,A++,38\n"
    "Consul,CRD15,6,B,22\n"
)
CSV_PT_HEADERS = (
    "fabricante,modelo,categoria,etiqueta,consumo_kwh_mes\nElectrolux,DC50,2,A,30\n"
)


# ------------------------------------------------------------------ #
# Helpers
# ------------------------------------------------------------------ #


def make_client(content: str) -> InmetroClient:
    return InmetroClient(csv_content=content)


def normalize_row(content: str, index: int = 0) -> Any:
    adapter = InmetroAdapter(client=make_client(content))
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
        assert isinstance(InmetroAdapter(), SourceAdapter)

    def test_client_requires_content_or_path(self) -> None:
        with pytest.raises(ValueError, match="csv_content ou csv_path"):
            InmetroClient()

    def test_discover_returns_refrigerators_dataset(self) -> None:
        datasets = make_client(CSV_OK).discover()
        assert datasets == [(DATASET_ID, "INMETRO PBE — Refrigeradores")]


# ------------------------------------------------------------------ #
# Identidade deterministica
# ------------------------------------------------------------------ #


class TestDeterministicIdentity:
    def test_uuid_stable_for_same_brand_model(self) -> None:
        p1 = normalize_row(CSV_OK)
        p2 = normalize_row(CSV_OK)
        assert p1 is not None and p2 is not None
        assert p1.product_id() == p2.product_id()

    def test_uuid_differs_between_products(self) -> None:
        p1 = normalize_row(CSV_OK, index=0)  # Electrolux DC50
        p2 = normalize_row(CSV_OK, index=1)  # Brastemp BRK47
        assert p1 is not None and p2 is not None
        assert p1.product_id() != p2.product_id()

    def test_dedup_key_uses_inmetro_prefix(self) -> None:
        product = normalize_row(CSV_OK)
        assert product is not None
        assert product.dedup_key() == "INMETRO|electrolux|dc50"

    def test_uuid_differs_from_energy_star_same_identity(self) -> None:
        """D7=A: mesmo brand/model em outra fonte => outro UUID."""
        from tests.conftest import make_product

        inmetro = normalize_row(CSV_OK)
        assert inmetro is not None
        es = make_product(
            source_id="Electrolux|DC50",
        )
        assert inmetro.product_id() != es.product_id()


# ------------------------------------------------------------------ #
# Normalizacao — campos obrigatorios e conversoes
# ------------------------------------------------------------------ #


class TestNormalizeFields:
    def test_brand_and_model_required(self) -> None:
        product = normalize_row("marca,modelo,kwh_mes\n,DC50,30\n")
        assert product is None

    def test_discards_without_consumption(self) -> None:
        product = normalize_row("marca,modelo,kwh_mes\nElectrolux,DC50,\n")
        assert product is None

    def test_annual_is_monthly_times_twelve(self) -> None:
        product = normalize_row(CSV_OK)
        assert product is not None
        assert product.annual_energy_kwh == Decimal("360.00")  # 30 x 12

    def test_source_is_inmetro(self) -> None:
        product = normalize_row(CSV_OK)
        assert product is not None
        assert product.source == "INMETRO"

    def test_is_generic_false(self) -> None:
        product = normalize_row(CSV_OK)
        assert product is not None
        assert product.is_generic is False

    def test_avg_power_is_none(self) -> None:
        """PBE nao declara potencia instantanea (nao inventar)."""
        product = normalize_row(CSV_OK)
        assert product is not None
        assert product.avg_power_w is None

    def test_category_maps_to_appliances(self) -> None:
        product = normalize_row(CSV_OK)
        assert product is not None
        assert product.category == "Eletrodomésticos"


# ------------------------------------------------------------------ #
# Classes ENCE (label_class)
# ------------------------------------------------------------------ #


class TestLabelClass:
    def test_extracts_valid_label(self) -> None:
        product = normalize_row(CSV_OK)  # classe A
        assert product is not None
        assert product.label_class == "A"

    def test_extracts_a_plus_plus(self) -> None:
        product = normalize_row(CSV_OK, index=1)
        assert product is not None
        assert product.label_class == "A++"

    def test_invalid_label_becomes_none(self) -> None:
        product = normalize_row(
            "marca,modelo,categoria,classe,kwh_mes\nElectrolux,DC50,1,X,30\n"
        )
        assert product is not None
        assert product.label_class is None

    def test_missing_label_is_none(self) -> None:
        product = normalize_row("marca,modelo,kwh_mes\nElectrolux,DC50,30\n")
        assert product is not None
        assert product.label_class is None


# ------------------------------------------------------------------ #
# Categorias oficiais -> subcategorias
# ------------------------------------------------------------------ #


class TestSubcategories:
    @pytest.mark.parametrize(
        ("row_category", "expected_subcategory"),
        [
            ("1", "Geladeira"),
            ("2", "Frost Free"),
            ("3", "Geladeira"),
            ("4", "Combinado"),
            ("5", "Combinado Frost Free"),
            ("6", "Congelador"),
        ],
    )
    def test_official_category_digits(
        self, row_category: str, expected_subcategory: str
    ) -> None:
        product = normalize_row(
            f"marca,modelo,categoria,kwh_mes\nElectrolux,DC50,{row_category},30\n"
        )
        assert product is not None
        assert product.subcategory == expected_subcategory

    def test_category_text_variant(self) -> None:
        product = normalize_row(
            "marca,modelo,categoria,kwh_mes\nElectrolux,DC50,Combinado,30\n"
        )
        assert product is not None
        assert product.subcategory == "Combinado"

    def test_category_with_prefix_extract_digit(self) -> None:
        """'Categoria 1' / '1 - Refrigerador' -> extrai o digito."""
        product = normalize_row(
            "marca,modelo,categoria,kwh_mes\nElectrolux,DC50,Categoria 1,30\n"
        )
        assert product is not None
        assert product.subcategory == "Geladeira"

    def test_unknown_category_falls_back_to_taxonomy(self) -> None:
        product = normalize_row(
            "marca,modelo,categoria,kwh_mes\nElectrolux,DC50,99,30\n"
        )
        assert product is not None
        # Fallback: subcategory padrao do slug 'refrigerators' = Geladeira
        assert product.subcategory == "Geladeira"


# ------------------------------------------------------------------ #
# Transporte/paginacao
# ------------------------------------------------------------------ #


class TestTransport:
    def test_fetch_page_slices(self) -> None:
        client = make_client(CSV_OK)
        assert client.fetch_page(DATASET_ID, limit=1, offset=1) == [
            {
                "marca": "Brastemp",
                "modelo": "BRK47",
                "categoria": "5",
                "classe": "A++",
                "kwh_mes": "38",
            }
        ]

    def test_count(self) -> None:
        assert make_client(CSV_OK).count(DATASET_ID) == 3

    def test_iter_respects_limit(self) -> None:
        adapter = InmetroAdapter(client=make_client(CSV_OK))
        pages = list(
            adapter.iter_raw_records(dataset_id=DATASET_ID, page_size=1, limit=2)
        )
        assert sum(len(recs) for _o, recs in pages) == 2

    def test_iter_requires_client(self) -> None:
        with pytest.raises(RuntimeError, match="InmetroClient"):
            next(InmetroAdapter().iter_raw_records(dataset_id=DATASET_ID, page_size=10))

    def test_pt_headers_are_accepted(self) -> None:
        """fabricante/etiqueta/consumo_kwh_mes (alias PT) funcionam."""
        product = normalize_row(CSV_PT_HEADERS)
        assert product is not None
        assert product.brand == "Electrolux"
        assert product.label_class == "A"
        assert product.annual_energy_kwh == Decimal("360.00")
