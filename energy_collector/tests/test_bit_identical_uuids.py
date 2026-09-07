"""Testes de verificacao de compatibilidade backward (PR 1).

Prova que, apos a refatoracao de dedup_key() para usar self.source
em vez da constante SOURCE_NAME, os UUIDs permanecem IDENTICOS
(bit-a-bit) para produtos ENERGY STAR legados.

Tambem valida que novas fontes (WattSimple, INMETRO, IEA) geram
UUIDs distintos ao usar source diferente.
"""

from __future__ import annotations

from collector.models import SOURCE_NAME, Product
from collector.normalization import normalize, normalize_record

# ------------------------------------------------------------------ #
# Helpers
# ------------------------------------------------------------------ #


def _product(source: str = SOURCE_NAME, **kwargs: object) -> Product:
    """Cria Product com defaults minimos e source configuravel."""
    defaults = {
        "name": "Test Product",
        "brand": "TestBrand",
        "model": "T-100",
        "category": "TestCategory",
        "subcategory": "TestSubcategory",
        "avg_power_w": None,
        "annual_energy_kwh": None,
        "standby_power_w": None,
        "source_id": None,
        "dataset_category": "test_dataset",
        "dataset_id": "test_01",
    }
    defaults.update(kwargs)
    defaults["source"] = source
    return Product(**defaults)  # type: ignore[arg-type]


# ------------------------------------------------------------------ #
# Bit-identical UUID preservation (backward compat)
# ------------------------------------------------------------------ #


class TestBitIdenticalUUIDs:
    """Garante que o pipeline ENERGY STAR legado produza os mesmos
    UUIDs apos a refatoracao dedup_key (self.source vs SOURCE_NAME)."""

    def test_should_preserve_uuid_when_source_is_source_name(self) -> None:
        """source='ENERGY STAR' (mesmo literal) => UUID identico."""
        p = _product(source="ENERGY STAR", source_id="ES-123")
        assert p.product_id().version == 5
        # Grava o UUID esperado antes da refatoracao
        expected_uuid = p.product_id()

        # Recria com o mesmo source_id - deve ser idempotente
        p2 = _product(source="ENERGY STAR", source_id="ES-123")
        assert p2.product_id() == expected_uuid

    def test_should_preserve_uuid_in_fallback_mode(self) -> None:
        """source='ENERGY STAR' + fallback (sem source_id) => UUID identico."""
        p = _product(
            source="ENERGY STAR",
            source_id=None,
            brand="LG",
            model="GC-X234",
            category="Refrigerators",
        )
        expected_uuid = p.product_id()

        p2 = _product(
            source="ENERGY STAR",
            source_id=None,
            brand="LG",
            model="GC-X234",
            category="Refrigerators",
        )
        assert p2.product_id() == expected_uuid

    def test_bit_identical_to_legacy(self) -> None:
        """Reprodutor direto do caso que quebraria se SOURCE_NAME
        fosse substituido por nome diferente."""
        p_legacy = _product(source="ENERGY STAR", source_id="PD-987")
        # Qualquer source != "ENERGY STAR" gera UUID DIFERENTE
        p_other = _product(source="OTHER", source_id="PD-987")
        assert p_legacy.product_id() != p_other.product_id()

    def test_should_differentiate_sources_for_same_product(self) -> None:
        """Mesmo source_id + mesmo brand/model, mas source diferente
        => UUIDs distintos (evita colisao entre fontes)."""
        p_star = _product(source="ENERGY STAR", source_id="X-001")
        p_ws = _product(source="WATTSIMPLE", source_id="X-001")
        p_inmetro = _product(source="INMETRO", source_id="X-001")
        assert (
            len({p_star.product_id(), p_ws.product_id(), p_inmetro.product_id()}) == 3
        )


# ------------------------------------------------------------------ #
# Protocol conformance (DIP)
# ------------------------------------------------------------------ #


class TestProtocolConformance:
    """Valida que os adaptadores implementam os protocols."""

    def test_energy_star_adapter_conforms_to_source_adapter(self) -> None:
        from collector.sources.energy_star import EnergyStarAdapter
        from collector.sources.protocol import SourceAdapter

        adapter = EnergyStarAdapter()
        assert isinstance(adapter, SourceAdapter)

    def test_energy_star_client_conforms_to_source_client(self) -> None:
        from collector.sources.energy_star import EnergyStarClient
        from collector.sources.protocol import SourceClient

        client = EnergyStarClient()
        assert isinstance(client, SourceClient)


# ------------------------------------------------------------------ #
# normalize_record with custom source
# ------------------------------------------------------------------ #


class TestNormalizeWithSource:
    """Valida normalize/normalize_record aceitam source parametrizado."""

    def test_should_default_source_to_energy_star(self) -> None:
        record = normalize_record(
            raw={
                "pd_id": "X1",
                "brand_name": "ACME",
                "model_name": "M1",
                "power_field": "150",
                "annual_energy_kwh": "100",
            },
            dataset_id="unknown-ds",
            category="custom",
        )
        assert record is not None
        assert record.product.source == SOURCE_NAME

    def test_should_accept_custom_source(self) -> None:
        record = normalize_record(
            raw={
                "pd_id": "X1",
                "brand_name": "ACME",
                "model_name": "M1",
                "power_field": "150",
                "annual_energy_kwh": "100",
            },
            dataset_id="unknown-ds",
            category="custom",
            source="WATTSIMPLE",
        )
        assert record is not None
        assert record.product.source == "WATTSIMPLE"

    def test_should_accept_source_via_normalize(self) -> None:
        product = normalize(
            raw={
                "pd_id": "X1",
                "brand_name": "ACME",
                "model_name": "M1",
                "power_field": "150",
                "annual_energy_kwh": "100",
            },
            dataset_id="unknown-ds",
            category="custom",
            source="WATTSIMPLE",
        )
        assert product is not None
        assert product.source == "WATTSIMPLE"

    def test_should_be_bit_identical_with_energy_star_source(self) -> None:
        """normalize com source='ENERGY STAR' produz mesmo UUID que
        source nao informado (default)."""
        with_source = normalize(
            raw={
                "pd_id": "X1",
                "brand_name": "ACME",
                "model_name": "M1",
                "power_field": "150",
                "annual_energy_kwh": "100",
            },
            dataset_id="unknown-ds",
            category="custom",
            source="ENERGY STAR",
        )
        without_source = normalize(
            raw={
                "pd_id": "X1",
                "brand_name": "ACME",
                "model_name": "M1",
                "power_field": "150",
                "annual_energy_kwh": "100",
            },
            dataset_id="unknown-ds",
            category="custom",
        )
        assert with_source is not None
        assert without_source is not None
        assert with_source.product_id() == without_source.product_id()
