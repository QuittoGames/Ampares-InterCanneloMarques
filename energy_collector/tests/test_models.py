from dataclasses import replace

from collector.models import Product


def _stable() -> Product:
    return Product(brand="A", model="B", category="cat")


def test_accepts_valid_product():
    ok, reason = _stable().validate()
    assert ok is True
    assert reason is None


def test_rejects_without_stable_identifier():
    ok, reason = Product().validate()
    assert ok is False
    assert "missing stable identifier" in (reason or "")


def test_rejects_negative_power():
    # Regression: validation must read `avg_power_w` (the field normalize writes),
    # not a misspelled `average_power_w`.
    ok, reason = replace(_stable(), avg_power_w=-1.0).validate()
    assert ok is False
    assert "negative power" in (reason or "")


def test_rejects_negative_energy():
    ok, reason = replace(_stable(), annual_energy_kwh=-5.0).validate()
    assert ok is False
    assert "negative energy" in (reason or "")
