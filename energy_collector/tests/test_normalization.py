"""Testes unitarios do normalizer (normalizacao segura e deterministica).

Cobre o contrato exigido:

* Tipos numericos: ``"100"`` -> 100, ``"100.5"`` -> 100.5, ``"100,5"``.
* Valores vazios: ``""``, ``null``, ``None``, ``"NULL"`` -> None.
* Strings: whitespace colapsado, vazias -> None.
* Campos de energia: equivalencias obvias de nomes.
* Rastreabilidade: SOURCE (``raw_*``, valor/periodo brutos, tensao
  declarada) preservado sem alteracao.
* Sem engine de formulas no coletor: horas/custos/consumo derivado sao
  responsabilidade do Java (Banco de Formulas) — o normalizer NAO os
  calcula (spec secao 5).
"""

from __future__ import annotations

from decimal import Decimal

import pytest

from collector.models import NormalizedProduct, Product
from collector.normalization import (
    _to_decimal,
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

    def test_ignore_sleep_and_off_power_for_avg_power(self) -> None:
        # REGRESSAO (bug real KIP 700): power_in_sleep_w (0.92W) NAO e a
        # potencia media de uso — a potencia real de uma impressora grande
        # e 600-1500W e nao e publicada. Sem coluna de uso -> None.
        raw = {
            "pd_id": "2394549",
            "brand_name": "KIP",
            "model_name": "KIP 700",
            "power_in_sleep_w": "0.92",
            "power_in_standby_w": "0.15",
            "dfe_sleep_mode_power_w": "1.50",
            "typical_electricity_consumption_tec_kwh_yr": "83.2",
        }
        rec = normalize_record(raw, "t2v6-g4nf", "imaging_equipment")
        assert rec is not None
        assert rec.avg_power_w is None  # sleep/standby NUNCA e potencia de uso
        assert rec.annual_energy_kwh == Decimal("83.2")

    def test_ignore_weekly_tec_as_annual_energy(self) -> None:
        # REGRESSAO (bug real): tec_kwh_wk (SEMANAL) casado como anual
        # falsificava o valor em ~52x (0.6 kWh/wk -> 0.6 kWh/ano).
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            "power_in_sleep_w": "0.9",
            "dfe_typical_electricity_consumption_tec_kwh_wk": "0.6",
        }
        rec = normalize_record(raw, "unknown-ds", "custom")
        assert rec is not None
        assert rec.annual_energy_kwh is None  # semanal NAO e anual


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
# Proveniencia de fonte: valores brutos, tensao e sem engine de formulas
# ---------------------------------------------------------------------------


class TestSourceProvenance:
    def test_extract_standby_power_from_record(self) -> None:
        # O campo de standby deve ser reconhecido e extraido (nao ignorado).
        # Ele vai para a OBSERVACAO de origem — nao para product (spec 1/7).
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
        assert rec.standby_power_w == Decimal("0.5")
        assert rec.product.standby_power_w == Decimal("0.5")

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
        # Valor bruto de energia + unidade/periodo originais (spec 5).
        assert rec.product.raw_energy_value == Decimal("200.0")
        assert rec.product.raw_energy_unit == "kWh/year"
        assert rec.product.avg_power_w == rec.raw_power
        assert isinstance(rec.product, Product)
        assert isinstance(rec, NormalizedProduct)

    def test_no_formula_engine_in_collector(self) -> None:
        # Banco de Formulas (horas, custos, consumo, tarifa) e do Java.
        # O coletor nao expoe engine de formulas concorrente (spec 5).
        import inspect

        import collector.normalization as normalization

        for removed in (
            "compute_derived",
            "compute_equivalent_hours_year",
            "compute_equivalent_hours_year_day",
            "compute_estimated_daily_energy",
            "compute_estimated_cost",
            "compute_standby_energy_kwh",
        ):
            assert not hasattr(normalization, removed), removed
        assert "tariff_per_kwh" not in inspect.signature(normalize_record).parameters

    def test_voltage_declaration_is_provenance_only(self) -> None:
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            "annual_energy_use_kwh": "200",
            "voltage": "220 V",
        }
        rec = normalize_record(raw, "unknown-ds", "custom")
        assert rec is not None
        assert rec.product.voltage_raw == "220 V"
        assert rec.product.voltage_kind == "monovolt"
        assert rec.product.voltage_min_v == Decimal("220")
        assert rec.product.voltage_max_v == Decimal("220")

    def test_missing_voltage_is_unknown_never_inferred(self) -> None:
        raw = {
            "pd_id": "X1",
            "brand_name": "ACME",
            "model_name": "M1",
            "annual_energy_use_kwh": "200",
        }
        rec = normalize_record(raw, "unknown-ds", "custom")
        assert rec is not None
        assert rec.product.voltage_kind == "unknown"
        assert rec.product.voltage_raw is None
        assert rec.product.voltage_min_v is None
        assert rec.product.voltage_max_v is None


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
