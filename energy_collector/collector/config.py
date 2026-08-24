"""Configuration and ENERGY STAR dataset catalogue.

This module is responsible for:
- Loading database credentials exclusively from environment variables (or .env).
- Loading the optional SOCRATA_APP_TOKEN.
- Mapping logical category names to real ENERGY STAR / Socrata datasets.

No credentials are ever hardcoded here. The *decision* of which dataset to use
lives in the collection service; this module only holds the data.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from urllib.parse import quote

from dotenv import load_dotenv

logger = logging.getLogger(__name__)

SOCRATA_BASE = "https://data.energystar.gov"
RESOURCE_URL = SOCRATA_BASE + "/resource/{dataset_id}.json"
CATALOG_URL = SOCRATA_BASE + "/api/catalog/v1"

# Logical category -> human search query used to discover the dataset id
# when it is not already known.
CATEGORY_SEARCH: dict[str, str] = {
    "refrigerators": "ENERGY STAR Certified Residential Refrigerators",
    "clothes_washers": "ENERGY STAR Certified Residential Clothes Washers",
    "clothes_dryers": "ENERGY STAR Certified Clothes Dryers",
    "dishwashers": "ENERGY STAR Certified Dishwashers",
    "televisions": "ENERGY STAR Certified Televisions",
    "computers": "ENERGY STAR Certified Computers",
    "displays": "ENERGY STAR Certified Displays",
    "room_air_conditioners": "ENERGY STAR Certified Room Air Conditioners",
    "freezers": "ENERGY STAR Certified Freezers",
    "electric_cooking_products": "ENERGY STAR Certified Cooking Products",
    "ceiling_fans": "ENERGY STAR Certified Ceiling Fans",
    "ventilating_fans": "ENERGY STAR Certified Ventilating Fans",
}

# Datasets whose Socrata 4x4 id and exact field mapping we have verified by
# reading the live API. These avoid any guessing for the most common categories.
KNOWN_DATASETS: dict[str, dict] = {
    "refrigerators": {
        "dataset_id": "p5st-her9",
        "brand": "brand_name",
        "model": "model_number",
        "annual_energy_kwh": "annual_energy_use_kwh_yr",
        "power_w": None,  # source provides annual kWh, not power
    },
    "televisions": {
        "dataset_id": "pd96-rr3d",
        "brand": "brand_name",
        "model": "model_name",
        "annual_energy_kwh": "reported_annual_energy_consumption_kwh",
        "power_w": "power_consumption_in_on_mode_watts",
    },
    "computers": {
        "dataset_id": "rxdj-2c88",
        "brand": "brand_name",
        "model": "model_name",
        "annual_energy_kwh": "tec_of_model_kwh",
        "power_w": None,  # only mode-specific watts available
    },
    "clothes_washers": {
        "dataset_id": "bghd-e2wd",
        "brand": "brand_name",
        "model": "model_number",
        "annual_energy_kwh": "annual_energy_use_kwh_yr",
        "power_w": None,
    },
}


@dataclass
class DbConfig:
    """Resolved database connection configuration."""

    conninfo: str

    @classmethod
    def from_env(cls) -> "DbConfig":
        load_dotenv()

        # 1) Explicit full URL wins (e.g. a ready Supabase URI from .env).
        database_url = os.getenv("DATABASE_URL")
        if database_url:
            return cls(conninfo=database_url.strip())

        # 2) Otherwise build the connection URL from the individual .env
        #    parameters (DB_HOST / DB_PORT / DB_NAME / DB_USER / DB_PASSWORD).
        host = os.getenv("DB_HOST")
        port = os.getenv("DB_PORT", "5432")
        name = os.getenv("DB_NAME")
        user = os.getenv("DB_USER")
        password = os.getenv("DB_PASSWORD")

        missing = [
            k
            for k, v in (
                ("DB_HOST", host),
                ("DB_NAME", name),
                ("DB_USER", user),
                ("DB_PASSWORD", password),
            )
            if not v
        ]
        if missing:
            raise RuntimeError(
                "No database configuration found. Provide DATABASE_URL or the "
                "following variables: " + ", ".join(missing)
            )

        # After the check above none of these are None. Assert to narrow types.
        assert host is not None and name is not None
        assert user is not None and password is not None

        # Build a standard Postgres URI. Credentials are URL-encoded (including
        # '/') so special characters in the password (common on Supabase) don't
        # break the URI parser.
        conninfo = (
            f"postgresql://{quote(user, safe='')}:{quote(password, safe='')}@"
            f"{host}:{port}/{quote(name, safe='')}"
        )
        return cls(conninfo=conninfo)


def get_app_token() -> str | None:
    """Return the Socrata app token if configured, else None (anonymous)."""
    load_dotenv()
    token = os.getenv("SOCRATA_APP_TOKEN")
    return token.strip() if token else None
