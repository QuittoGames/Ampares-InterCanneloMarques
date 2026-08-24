"""Typed domain model for the collector.

``Product`` is the single source of truth for the product shape. Normalisation
produces a ``Product``; validation and id-derivation live here as methods, so
every layer works with the same typed object instead of ad-hoc dicts keyed by
hand-written strings (which is what caused a field-name typo bug before).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

# Business constant (also used to derive the deterministic id).
SOURCE_NAME = "ENERGY STAR"

# Stable namespace so the same key always yields the same UUID across runs.
_NAMESPACE = uuid.NAMESPACE_URL


@dataclass
class Product:
    name: str | None = None
    brand: str | None = None
    model: str | None = None
    category: str | None = None
    avg_power_w: float | None = None
    annual_energy_kwh: float | None = None
    source: str = SOURCE_NAME
    source_id: str | None = None

    # ------------------------------------------------------------------ #
    # Identity (deterministic, idempotent upsert key)
    # ------------------------------------------------------------------ #
    def dedup_key(self) -> str:
        """Stable key: source_id wins; falls back to brand+model+category."""
        if self.source_id:
            return f"{self.source}::{self.source_id}"
        return f"{self.source}::{self.brand}::{self.model}::{self.category}"

    def product_id(self) -> uuid.UUID:
        """Deterministic UUID primary key (matches the JPA ``Product.id``)."""
        return uuid.uuid5(_NAMESPACE, self.dedup_key())

    # ------------------------------------------------------------------ #
    # Rules
    # ------------------------------------------------------------------ #
    def validate(self) -> tuple[bool, str | None]:
        """Return ``(is_valid, reject_reason)``. Never guesses a value."""
        if not self.source_id and not (self.brand and self.model and self.category):
            return (
                False,
                "missing stable identifier (source_id or brand+model+category)",
            )
        if self.avg_power_w is not None and self.avg_power_w < 0:
            return False, f"negative power: {self.avg_power_w}"
        if self.annual_energy_kwh is not None and self.annual_energy_kwh < 0:
            return False, f"negative energy: {self.annual_energy_kwh}"
        return True, None
