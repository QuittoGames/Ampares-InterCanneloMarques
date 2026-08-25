"""Testes unitarios de ``collector.models``.

Cobre a canonicalizacao (NFKC + casefold + whitespace), a chave de
deduplicacao (``source_id`` vence; fallback marca+modelo+categoria), a
determinismo do ``product_id`` (uuid5) e as regras de ``validate``.
"""

from __future__ import annotations

import uuid

import pytest

from collector.models import SOURCE_NAME, Product, canonical, stable_uuid

from .conftest import make_product  # noqa: TID252 - helper do pacote de testes


class TestCanonical:
    @pytest.mark.parametrize("value", [None, "", "   "])
    def should_return_empty_string_for_empty_input(self, value: str | None) -> None:
        assert canonical(value) == ""

    def should_casefold_and_collapse_whitespace(self) -> None:
        assert canonical("  Mixed   CASE \t\n Value  ") == "mixed case value"

    def should_apply_nfkc_compatibility(self) -> None:
        assert canonical("ＦＵＬＬＷＩＤＴＨ") == "fullwidth"
        assert canonical("ﬁle") == "file"  # ligadura U+FB01 -> "fi"

    def should_casefold_german_sharp_s(self) -> None:
        assert canonical("Straße") == "strasse"


class TestDedupKey:
    def should_prefer_source_id_over_brand_model(self) -> None:
        product = make_product(
            source_id=" PD-9 ", brand="SomeBrand", model="M-1", category="cat"
        )

        key = product.dedup_key()

        assert key == f"{SOURCE_NAME}|pd-9"
        assert "somebrand" not in key

    def should_fall_back_to_brand_model_category(self) -> None:
        product = make_product(
            source_id=None, brand=" Acme ", model="X  900", category="Refrigerators"
        )

        assert product.dedup_key() == f"{SOURCE_NAME}|acme|x 900|refrigerators"


class TestProductId:
    def should_be_deterministic_for_same_input(self) -> None:
        first = make_product(source_id="PD-123")
        second = make_product(source_id="PD-123")

        assert isinstance(first.product_id(), uuid.UUID)
        assert first.product_id() == second.product_id()
        assert stable_uuid(first) == first.product_id()

    def should_be_uuid5(self) -> None:
        # Contrato FR-004: identidade deterministic via uuid5.
        assert make_product().product_id().version == 5

    def should_ignore_case_and_spacing_variations_in_fallback(self) -> None:
        spaced = make_product(
            source_id=None, brand=" ACME ", model="Model  X", category="TVs"
        )
        clean = make_product(
            source_id=None, brand="acme", model="model x", category="tvs"
        )

        assert spaced.product_id() == clean.product_id()

    def should_ignore_source_id_case_variations(self) -> None:
        assert (
            make_product(source_id="ES-ABC").product_id()
            == make_product(source_id="es-abc").product_id()
        )

    def should_change_when_identity_changes(self) -> None:
        base = make_product(source_id=None, brand="acme", model="x", category="c")

        by_model = make_product(source_id=None, brand="acme", model="y", category="c")
        by_category = make_product(
            source_id=None, brand="acme", model="x", category="tv"
        )
        by_source_id = make_product(source_id="SID-B")

        assert base.product_id() != by_model.product_id()
        assert base.product_id() != by_category.product_id()
        assert make_product(source_id="SID-A").product_id() != by_source_id.product_id()


class TestValidate:
    def should_accept_source_id_alone(self) -> None:
        ok, reason = make_product(source_id="PD-1", brand=None, model=None).validate()
        assert (ok, reason) == (True, None)

    def should_accept_brand_and_model_without_source_id(self) -> None:
        ok, reason = make_product(source_id=None, brand="A", model="B").validate()
        assert (ok, reason) == (True, None)

    @pytest.mark.parametrize(
        "brand,model",
        [("A", None), (None, "B"), (None, None), ("", "")],
    )
    def should_reject_without_stable_identification(
        self, brand: str | None, model: str | None
    ) -> None:
        ok, reason = make_product(source_id=None, brand=brand, model=model).validate()

        assert ok is False
        assert reason is not None and "identificador" in reason

    def should_reject_empty_category_even_with_source_id(self) -> None:
        ok, reason = make_product(source_id="PD-1", category="").validate()

        assert ok is False
        assert reason is not None and "category" in reason

    def should_reject_empty_category_with_brand_model(self) -> None:
        ok, _reason = make_product(
            source_id=None, brand="A", model="B", category=""
        ).validate()

        assert ok is False
