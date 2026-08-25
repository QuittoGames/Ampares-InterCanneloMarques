"""Testes unitarios do normalizer (normalizacao segura e deterministica).

Cobre o contrato exigido:

* Tipos numericos: ``"100"`` -> 100, ``"100.5"`` -> 100.5, ``"100,5"``.
* Valores vazios: ``""``, ``null``, ``None``, ``"NULL"`` -> None.
* Strings: whitespace colapsado, vazias -> None.
* Campos de energia: equivalencias obvias de nomes.
* Derivados: ``equivalent_hours_year`` a partir de ``avg_power_w`` +
  ``annual_energy_kwh``; divisao por zero tratada (``power=0``).
* Rastreabilidade: SOURCE (``raw_*``) separado de DERIVED.
"""

from __future__ import annotations

from decimal import Decimal

import pytest

from collector.models import NormalizedProduct, Product
from collector.normalization import (
    _to_decimal,
    compute_derived,
    compute_equivalent_hours_year,
    compute_equivalent_hours_year_day,
    compute_estimated_cost,
    compute_estimated_daily_energy,
    normalize,
    normalize_record,
)


# ---------------------------------------------------------------------------
# Conversao numerica (_to_decimal)
# ---------------------------------------------------------------------------


class TestToDecimal:
    @pytest.mark.parametrize(
        "value,expected",
        [
            ("100", Decimal("100.0")),
            ("100.5", Decimal("100.5")),
            ("100,5", Decimal("100.5")),  # virgula decimal segura
            (100, Decimal("100.0")),
            (100.0, Decimal("100.0")),
            ("100.0", Decimal("100.0")),
        ],
    )
    def test_convert_numeric_formats(self, value, expected) -> None:
        assert _to_decimal(value, "field") == expected

    @pytest.mark.parametrize("value", ["", None, "null", "NULL", "None", "nan"])
    def test_return_none_for_empty_or_null(self, value) -> None:
        assert _to_decimal(value, "field") is None

    @pytest.mark.parametrize("value", ["-5", "abc", "Infinity", "1,000,000"])
    def test_return_none_for_invalid(self, value) -> None:
        assert _to_decimal(value, "field") is None


# ---------------------------------------------------------------------------
# Equivalencias de campos de energia (normalize_record)
# ---------------------------------------------------------------------------


class TestEnergyFieldEquivalents:
    @pytest.mark.parametrize(
        "power_field",
        [
            "power",
            "watts",
            "power_watts",
            "rated_power_watts",
            "avg_power_w",
        ],
    )
    def test_recognize_power_field(self, power_field) -> None:
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            power_field: "150",
            "annual_energy_use_kwh": "100",
        }
        rec = normalize_record(raw, "unknown-ds", "custom")
        assert rec is not None
        assert rec.avg_power_w == Decimal("150.0")

    @pytest.mark.parametrize(
        "annual_field",
        [
            "annual_energy_kwh",
            "annual_energy_use_kwh",
            "annual_energy_use_kwh_year",
            "annual_consumption_kwh",
            "kwh_year",
            "reported_annual_energy_consumption_kwh",
        ],
    )
    def test_recognize_annual_field(self, annual_field) -> None:
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            "power_watts": "150",
            annual_field: "100",
        }
        rec = normalize_record(raw, "unknown-ds", "custom")
        assert rec is not None
        assert rec.annual_energy_kwh == Decimal("100.0")

    def test_ignore_standby_power_for_avg_power(self) -> None:
        # O campo de standby NAO deve virar a potencia media.
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            "power_consumption_in_on_mode_watts": "120",
            "power_consumption_in_standby_mode_when_network_connected_watts": "0.5",
            "annual_energy_use_kwh": "200",
        }
        rec = normalize_record(raw, "unknown-ds", "custom")
        assert rec is not None
        assert rec.avg_power_w == Decimal("120.0")


# ---------------------------------------------------------------------------
# Campos desconhecidos -> None (nao descarta o registro)
# ---------------------------------------------------------------------------


class TestUnknownFields:
    def test_keep_none_and_not_discard(self) -> None:
        raw = {"pd_id": "X1", "brand_name": "Foo", "model_name": "Bar"}
        rec = normalize_record(raw, "unknown-ds", "custom")
        assert rec is not None
        assert rec.avg_power_w is None
        assert rec.annual_energy_kwh is None
        assert rec.raw_power is None

    def test_discard_only_without_identification(self) -> None:
        # Sem source_id E sem marca+modelo -> descarte (None).
        raw = {"brand_name": "only_brand_no_model_no_id"}
        assert normalize_record(raw, "ds", "cat") is None


# ---------------------------------------------------------------------------
# Derivados: horas equivalentes, energia diaria, custo
# ---------------------------------------------------------------------------


class TestDerived:
    def test_compute_equivalent_hours_year(self) -> None:
        # H_eq = 1000 * 100 kWh / 100 W = 1000 h/ano
        hours = compute_equivalent_hours_year(Decimal("100"), Decimal("100"))
        assert hours == Decimal("1000.0")

    def test_avoid_division_by_zero(self) -> None:
        assert compute_equivalent_hours_year(Decimal("0"), Decimal("100")) is None
        assert compute_equivalent_hours_year(None, Decimal("100")) is None
        assert compute_equivalent_hours_year(Decimal("100"), None) is None

    def test_compute_daily_hours_and_energy(self) -> None:
        day = compute_equivalent_hours_year_day(Decimal("365"))
        assert day == Decimal("1.0")
        daily = compute_estimated_daily_energy(Decimal("365"))
        assert daily == Decimal("1.0")

    def test_compute_cost_from_explicit_tariff(self) -> None:
        cost = compute_estimated_cost(Decimal("100"), Decimal("0.60"))
        assert cost == Decimal("60.00")
        # Tarifa ausente -> None (nunca assumida arbitrariamente).
        assert compute_estimated_cost(Decimal("100"), None) is None

    def test_populate_derived_from_record(self) -> None:
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            "power_watts": "100",
            "annual_energy_use_kwh": "100",
        }
        rec = normalize_record(
            raw, "unknown-ds", "custom", tariff_per_kwh=Decimal("0.60")
        )
        assert rec is not None
        assert rec.equivalent_hours_year == Decimal("1000.0")
        assert rec.equivalent_hours_year_day == compute_equivalent_hours_year_day(
            rec.equivalent_hours_year
        )
        assert rec.estimated_daily_energy_kwh == compute_estimated_daily_energy(
            rec.annual_energy_kwh
        )
        assert rec.estimated_cost == Decimal("60.00")
        assert rec.tariff_per_kwh == Decimal("0.60")

    def test_keep_raw_source_data_separate(self) -> None:
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            "power_watts": "150",
            "annual_energy_use_kwh": "200",
        }
        rec = normalize_record(raw, "unknown-ds", "custom")
        assert rec is not None
        # SOURCE data preservado como veio (Decimal do valor bruto).
        assert rec.raw_power == Decimal("150.0")
        assert rec.raw_annual_energy == Decimal("200.0")
        # SOURCE != DERIVED semanticamente distintos.
        assert rec.product.avg_power_w == rec.raw_power
        assert isinstance(rec.product, Product)
        assert isinstance(rec, NormalizedProduct)


# ---------------------------------------------------------------------------
# normalize() mantido compativel (retorna Product)
# ---------------------------------------------------------------------------


class TestNormalizeCompat:
    def test_return_product_and_match_record(self) -> None:
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            "power_watts": "150",
            "annual_energy_use_kwh": "200",
        }
        product = normalize(raw, "unknown-ds", "custom")
        assert isinstance(product, Product)
        assert product.avg_power_w == Decimal("150.0")
        assert product.annual_energy_kwh == Decimal("200.0")

    def test_apply_known_dataset_mapping(self) -> None:
        # TV real (mapeamento verificado): power e annual vindos de colunas
        # especificas do KNOWN_DATASETS.
        raw = {
            "pd_id": "2402123",
            "brand_name": "RCA",
            "model_name": "65D1",
            "model_number": "65D1",
            "power_consumption_in_on_mode_watts": "117.69",
            "reported_annual_energy_consumption_kwh": "216.87",
        }
        rec = normalize_record(raw, "pd96-rr3d", "televisions")
        assert rec is not None
        assert rec.avg_power_w == Decimal("117.69")
        assert rec.annual_energy_kwh == Decimal("216.87")

    def test_extract_washer_annual_with_correct_column(self) -> None:
        # bghd-e2wd usa `annual_energy_use_kwh_year` (coluna real da API).
        raw = {
            "pd_id": "2545602",
            "brand_name": "AEG",
            "model_number": "W14120",
            "annual_energy_use_kwh_year": "110",
        }
        rec = normalize_record(raw, "bghd-e2wd", "clothes_washers")
        assert rec is not None
        assert rec.annual_energy_kwh == Decimal("110.0")
        assert rec.avg_power_w is None


# ---------------------------------------------------------------------------
# Testes originais (recuperados do HEAD) — cenarios de nao-regressao
# ---------------------------------------------------------------------------


class TestOriginalRegression:
    def test_refrigerator_annual_only_power_none(self) -> None:
        raw = {
            "pd_id": "abc-1",
            "brand_name": "Samsung",
            "model_number": "RF28T",
            "annual_energy_use_kwh_year": "500",
        }
        rec = normalize_record(raw, "refrigerators", "refrigerators")
        assert rec is not None
        assert rec.product.source == "ENERGY STAR"
        assert rec.product.source_id == "abc-1"
        assert rec.product.brand == "Samsung"
        assert rec.product.model == "RF28T"
        assert rec.product.name == "Samsung RF28T"
        assert rec.product.annual_energy_kwh == Decimal("500.0")
        assert rec.product.avg_power_w is None  # fonte fornece kWh, nao potencia

    def test_television_has_both_power_and_annual(self) -> None:
        raw = {
            "pd_id": "tv-9",
            "brand_name": "LG",
            "model_name": "OLED55",
            "power_consumption_in_on_mode_watts": "120",
            "reported_annual_energy_consumption_kwh": "200",
        }
        rec = normalize_record(raw, "pd96-rr3d", "televisions")
        assert rec is not None
        assert rec.product.avg_power_w == Decimal("120.0")
        assert rec.product.annual_energy_kwh == Decimal("200.0")
        assert rec.product.name == "LG OLED55"

    def test_missing_fields_stay_none_and_no_invention(self) -> None:
        # Sem marca, modelo, energia ou potencia -> campos None, sem descarte.
        raw = {"pd_id": "x-1"}
        rec = normalize_record(raw, "refrigerators", "refrigerators")
        assert rec is not None
        assert rec.product.brand is None
        assert rec.product.model is None
        assert rec.product.avg_power_w is None
        assert rec.product.annual_energy_kwh is None
