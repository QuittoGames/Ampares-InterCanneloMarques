from collector.normalization import normalize


def test_refrigerator_annual_only_power_none():
    raw = {
        "pd_id": "abc-1",
        "brand_name": "Samsung",
        "model_number": "RF28T",
        "annual_energy_use_kwh_yr": "500",
    }
    out = normalize(raw, "refrigerators")
    assert out.source == "ENERGY STAR"
    assert out.source_id == "abc-1"
    assert out.brand == "Samsung"
    assert out.model == "RF28T"
    assert out.name == "Samsung RF28T"
    assert out.annual_energy_kwh == 500.0
    assert out.avg_power_w is None  # source provides kWh, not power


def test_television_has_both_power_and_annual():
    raw = {
        "pd_id": "tv-9",
        "brand_name": "LG",
        "model_name": "OLED55",
        "power_consumption_in_on_mode_watts": "120",
        "reported_annual_energy_consumption_kwh": "200",
    }
    out = normalize(raw, "televisions")
    assert out.avg_power_w == 120.0
    assert out.annual_energy_kwh == 200.0
    assert out.name == "LG OLED55"


def test_missing_fields_stay_none_and_no_invention():
    raw = {"pd_id": "x-1"}  # no brand, model, energy or power
    out = normalize(raw, "refrigerators")
    assert out.brand is None
    assert out.model is None
    assert out.avg_power_w is None
    assert out.annual_energy_kwh is None
    assert out.name == "x-1"  # falls back to source_id, not invented text


def test_non_numeric_energy_becomes_none():
    raw = {
        "pd_id": "y-2",
        "brand_name": "Acme",
        "model_number": "M1",
        "annual_energy_use_kwh_yr": "N/A",
    }
    out = normalize(raw, "refrigerators")
    assert out.annual_energy_kwh is None
