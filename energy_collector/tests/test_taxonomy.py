"""Testes da taxonomia global de produtos (``collector.taxonomy``).

Cobre:
* O mapeamento exato (``CATEGORY_MAPPING``) para os cenarios da spec.
* O fallback por palavras-chave (datasets desconhecidos).
* O fallback final (``Outros / Nao categorizado``).
* A integracao com ``normalize``: a categoria do DATASET nunca vira a
  categoria final do produto.
"""

from __future__ import annotations

import pytest

from collector.normalization import normalize
from collector.models import Product
from collector.taxonomy import (
    CATEGORY_APPLIANCES,
    CATEGORY_AUTOMATION,
    CATEGORY_COMPUTING,
    CATEGORY_ELECTRONICS,
    CATEGORY_HVAC,
    CATEGORY_LIGHTING,
    CATEGORY_OTHER,
    UNCATEGORIZED,
    resolve_taxonomy,
)


class TestResolveTaxonomy:
    """Mapeamentos exatos definidos na spec."""

    @pytest.mark.parametrize(
        "slug, expected",
        [
            ("televisions", (CATEGORY_ELECTRONICS, "Televisão")),
            ("refrigerators", (CATEGORY_APPLIANCES, "Geladeira")),
            ("residential_refrigerators", (CATEGORY_APPLIANCES, "Geladeira")),
            ("residential_freezers", (CATEGORY_APPLIANCES, "Freezer")),
            ("residential_clothes_dryers", (CATEGORY_APPLIANCES, "Secadora")),
            ("residential_dishwashers", (CATEGORY_APPLIANCES, "Lava-louças")),
            ("residential_electric_cooking", (CATEGORY_APPLIANCES, "Fogão/Forno")),
            ("room_air_conditioners", (CATEGORY_HVAC, "Ar-condicionado")),
            ("room_air_cleaners_v3_0", (CATEGORY_HVAC, "Purificador de ar")),
            ("smart_thermostats", (CATEGORY_AUTOMATION, "Termostato")),
            ("imaging_equipment", (CATEGORY_ELECTRONICS, "Equipamento de imagem")),
            ("computers", (CATEGORY_COMPUTING, "Computador")),
            ("monitors", (CATEGORY_COMPUTING, "Monitor")),
            ("lamps", (CATEGORY_LIGHTING, "Lâmpada")),
            ("clothes_washers", (CATEGORY_APPLIANCES, "Lavadora")),
        ],
    )
    def should_map_known_slugs(self, slug: str, expected: tuple[str, str]) -> None:
        result = resolve_taxonomy(slug)
        assert (result["category"], result["subcategory"]) == expected

    def should_be_case_insensitive(self) -> None:
        assert resolve_taxonomy("Televisions") == resolve_taxonomy("televisions")


class TestKeywordFallback:
    """Datasets ainda nao mapeados caem no fallback por palavras-chave."""

    @pytest.mark.parametrize(
        "slug, expected",
        [
            # lâmpada por palavra-chave
            ("energy_star_led_lamps", (CATEGORY_LIGHTING, "Lâmpada")),
            # fogão/cooktop não mapeado exatamente
            ("residential_gas_ranges", (CATEGORY_APPLIANCES, "Fogão/Forno")),
            # ar-condicionado não mapeado exatamente
            ("window_air_conditioners", (CATEGORY_HVAC, "Ar-condicionado")),
            # máquina de lavar não mapeada exatamente
            ("commercial_washing_machines", (CATEGORY_APPLIANCES, "Lavadora")),
        ],
    )
    def should_match_unknown_slugs_via_keywords(
        self, slug: str, expected: tuple[str, str]
    ) -> None:
        result = resolve_taxonomy(slug)
        assert (result["category"], result["subcategory"]) == expected


class TestFallbackFinal:
    """Quando nada casa, usa Outros / Nao categorizado."""

    def should_use_others_for_unknown(self) -> None:
        result = resolve_taxonomy("some_obscure_thing")
        assert (result["category"], result["subcategory"]) == (
            CATEGORY_OTHER,
            UNCATEGORIZED,
        )

    def should_use_others_for_empty(self) -> None:
        assert resolve_taxonomy(None) == {
            "category": CATEGORY_OTHER,
            "subcategory": UNCATEGORIZED,
        }
        assert resolve_taxonomy("") == {
            "category": CATEGORY_OTHER,
            "subcategory": UNCATEGORIZED,
        }

    def should_not_invent_weak_categories(self) -> None:
        # "gadget" nao deve disparar regra nenhuma por substring fraca.
        result = resolve_taxonomy("wireless_gadget_accessories")
        assert result["category"] == CATEGORY_OTHER


class TestNormalizeIntegration:
    """A normalizacao usa a taxonomia global, nao o nome do dataset."""

    def _raw(
        self,
        *,
        brand: str = "Brand",
        model: str = "Model",
        power: str | None = None,
        annual: str | None = None,
    ) -> dict:
        raw: dict = {
            "pd_id": "SRC-1",
            "brand_name": brand,
            "model_number": model,
        }
        if power is not None:
            raw["power"] = power
        if annual is not None:
            raw["annual_energy_use_kwh_yr"] = annual
        return raw

    def _normalized(self, slug: str, raw: dict) -> Product:
        product = normalize(raw, "pd96-rr3d", slug)
        assert product is not None  # tem pd_id -> nunca descartado aqui
        return product

    def test_tv_maps_to_electronics_television(self) -> None:
        product = self._normalized("televisions", self._raw(power="150", annual="200"))
        assert product.category == CATEGORY_ELECTRONICS
        assert product.subcategory == "Televisão"
        # rastreabilidade preservada, mas nao como categoria final
        assert product.dataset_category == "televisions"
        assert product.dataset_id == "pd96-rr3d"

    def test_lamp_maps_to_lighting(self) -> None:
        product = normalize(
            {
                "pd_id": "L1",
                "brand_name": "Philips",
                "model_number": "LED",
                "power": "10",
            },
            "lamp-ds",
            "lamps",
        )
        assert product is not None
        assert product.category == CATEGORY_LIGHTING
        assert product.subcategory == "Lâmpada"

    def test_stove_maps_to_appliances(self) -> None:
        # slug nao mapeado exato -> fallback por keyword "stove"
        product = normalize(
            {"pd_id": "S1", "brand_name": "Consul", "model_number": "F60"},
            "stove-ds",
            "residential_stoves",
        )
        assert product is not None
        assert product.category == CATEGORY_APPLIANCES
        assert product.subcategory == "Fogão/Forno"

    def test_fridge_maps_to_appliances_fridge(self) -> None:
        product = self._normalized("refrigerators", self._raw(annual="500"))
        assert product.category == CATEGORY_APPLIANCES
        assert product.subcategory == "Geladeira"

    def test_ac_maps_to_hvac(self) -> None:
        product = self._normalized("room_air_conditioners", self._raw(annual="300"))
        assert product.category == CATEGORY_HVAC
        assert product.subcategory == "Ar-condicionado"

    def test_washing_machine_maps_to_appliances(self) -> None:
        product = self._normalized("clothes_washers", self._raw(annual="400"))
        assert product.category == CATEGORY_APPLIANCES
        assert product.subcategory == "Lavadora"

    def test_monitor_maps_to_computing(self) -> None:
        product = normalize(
            {
                "pd_id": "M1",
                "brand_name": "Dell",
                "model_number": "P2422",
                "power": "25",
            },
            "mon-ds",
            "monitors",
        )
        assert product is not None
        assert product.category == CATEGORY_COMPUTING
        assert product.subcategory == "Monitor"

    def test_computer_maps_to_computing(self) -> None:
        product = normalize(
            {
                "pd_id": "C1",
                "brand_name": "Lenovo",
                "model_number": "ThinkPad",
                "power": "65",
            },
            "comp-ds",
            "computers",
        )
        assert product is not None
        assert product.category == CATEGORY_COMPUTING
        assert product.subcategory == "Computador"

    def test_thermostat_maps_to_automation(self) -> None:
        product = normalize(
            {"pd_id": "T1", "brand_name": "Nest", "model_number": "E", "power": "3"},
            "therm-ds",
            "smart_thermostats",
        )
        assert product is not None
        assert product.category == CATEGORY_AUTOMATION
        assert product.subcategory == "Termostato"

    def test_unknown_equipment_falls_back_to_others(self) -> None:
        product = normalize(
            {"pd_id": "U1", "brand_name": "Foo", "model_number": "Bar"},
            "unk-ds",
            "some_obscure_category_xyz",
        )
        assert product is not None
        assert product.category == CATEGORY_OTHER
        assert product.subcategory == UNCATEGORIZED

    def test_subcategory_and_dataset_id_are_present(self) -> None:
        product = self._normalized("televisions", self._raw())
        assert product.subcategory  # nao vazio
        assert product.dataset_id == "pd96-rr3d"
        assert product.dataset_category == "televisions"
