"""Normalization layer.

Transforms a single raw ENERGY STAR record into a ``Product``.

Rules (from the spec):
- avg_power_w is set ONLY when the source truly provides power (watts).
- annual_energy_kwh is set ONLY when the source provides annual consumption.
- Metrics are NEVER converted into each other without valid math.
- Missing fields stay None; no arbitrary estimates are invented.
- Only intrinsic appliance attributes are kept. The ENERGY STAR API is a seed
  source: we do NOT preserve the raw payload or source URL (no raw_data /
  source_url). `source` / `source_id` are kept transiently only to derive a
  deterministic id for idempotent upserts.
"""

from __future__ import annotations

import logging
import re
from typing import Any

from .config import KNOWN_DATASETS
from .models import SOURCE_NAME, Product

logger = logging.getLogger(__name__)

POWER_RE = re.compile(r"power.*watt", re.IGNORECASE)
ANNUAL_RE = re.compile(
    r"annual.*kwh|kwh_yr|annual_energy|consumption.*kwh|tec_of_model_kwh", re.IGNORECASE
)


def _as_float(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _first_matching_key(raw: dict, pattern: re.Pattern) -> str | None:
    for key in raw:
        if pattern.search(key):
            return key
    return None


def normalize(raw: dict, category: str) -> Product:
    """Return a normalized ``Product`` for the given logical category."""
    cfg = KNOWN_DATASETS.get(category)

    if cfg:
        brand = raw.get(cfg["brand"])
        model = raw.get(cfg["model"])
        annual = (
            _as_float(raw.get(cfg["annual_energy_kwh"]))
            if cfg["annual_energy_kwh"]
            else None
        )
        power = _as_float(raw.get(cfg["power_w"])) if cfg["power_w"] else None
    else:
        # Generic, field-name-agnostic extraction for datasets we have not
        # inspected. Still uses only real keys present in the payload.
        brand = raw.get("brand_name") or raw.get("energy_star_partner")
        model = raw.get("model_name") or raw.get("model_number")
        power_key = _first_matching_key(raw, POWER_RE)
        annual_key = _first_matching_key(raw, ANNUAL_RE)
        power = _as_float(raw.get(power_key)) if power_key else None
        annual = _as_float(raw.get(annual_key)) if annual_key else None

    source_id = (
        raw.get("pd_id")
        or raw.get("energy_star_model_identifier")
        or raw.get("model_number")
    )

    name_parts = [str(p) for p in (brand, model) if p]
    name = " ".join(name_parts) if name_parts else (source_id or "unknown")

    return Product(
        name=name,
        brand=brand,
        model=model,
        category=category,
        avg_power_w=power,
        annual_energy_kwh=annual,
        source=SOURCE_NAME,
        source_id=source_id,
    )
