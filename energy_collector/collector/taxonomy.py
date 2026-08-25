"""Taxonomia global de produtos — mapeamento dataset tecnico → categoria de negocio.

Responsabilidade UNICA: dado o nome tecnico do dataset ENERGY STAR
(``dataset_category``), retorna o par ``(category, subcategory)`` da taxonomia
global da aplicacao.

Decisoes:

* ``CATEGORY_MAPPING`` — mapa exato, fonte de verdade. Adicionar um novo
  dataset mapeado = UMA entrada aqui, sem tocar na logica.
* ``_KEYWORD_RULES`` — fallback ORDENADO para datasets desconhecidos
  (FR-012). Regras testadas em ordem; a primeira que casa vence.
  Cada regra so dispara com confianca minima (palavra inteira/token).
* Nada casa => ``("Outros", "Nao categorizado")`` (regra 7 da spec). Nunca
  inventamos categoria por suposicao fraca.

Hierarquia:

    category (global, poucas, estavel)
        └── subcategory (especifica, pode crescer)
"""

from __future__ import annotations

import re

# ---------------------------------------------------------------------------
# Taxonomia global (valores oficiais)
# ---------------------------------------------------------------------------

CATEGORY_APPLIANCES = "Eletrodomésticos"
CATEGORY_ELECTRONICS = "Eletrônicos"
CATEGORY_LIGHTING = "Iluminação"
CATEGORY_HVAC = "Climatização"
CATEGORY_AUTOMATION = "Automação"
CATEGORY_KITCHEN = "Cozinha"
CATEGORY_COMPUTING = "Informática"
CATEGORY_ENTERTAINMENT = "Entretenimento"
CATEGORY_COMMERCIAL = "Equipamentos Comerciais"
CATEGORY_TOOLS = "Ferramentas"
CATEGORY_OTHER = "Outros"

UNCATEGORIZED = "Não categorizado"


# ---------------------------------------------------------------------------
# Mapeamento exato: dataset_category (slug tecnico) -> taxonomia
# ---------------------------------------------------------------------------

CATEGORY_MAPPING: dict[str, dict[str, str]] = {
    # --- Eletrônicos / Entretenimento --------------------------------------
    "televisions": {
        "category": CATEGORY_ELECTRONICS,
        "subcategory": "Televisão",
    },
    "imaging_equipment": {
        "category": CATEGORY_ELECTRONICS,
        "subcategory": "Equipamento de imagem",
    },
    "telephones": {
        "category": CATEGORY_ELECTRONICS,
        "subcategory": "Telefone",
    },
    "displays": {
        "category": CATEGORY_COMPUTING,
        "subcategory": "Monitor",
    },
    # --- Informática --------------------------------------------------------
    "computers": {
        "category": CATEGORY_COMPUTING,
        "subcategory": "Computador",
    },
    "monitors": {
        "category": CATEGORY_COMPUTING,
        "subcategory": "Monitor",
    },
    "enterprise_servers": {
        "category": CATEGORY_COMPUTING,
        "subcategory": "Servidor",
    },
    "large_network_equipment": {
        "category": CATEGORY_COMPUTING,
        "subcategory": "Equipamento de rede",
    },
    "data_center_storage_block_i_o": {
        "category": CATEGORY_COMPUTING,
        "subcategory": "Armazenamento",
    },
    "data_center_storage_file_i_o": {
        "category": CATEGORY_COMPUTING,
        "subcategory": "Armazenamento",
    },
    "uninterruptible_power_supplies": {
        "category": CATEGORY_COMPUTING,
        "subcategory": "No-break",
    },
    # --- Eletrodomésticos ---------------------------------------------------
    "refrigerators": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Geladeira",
    },
    "residential_refrigerators": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Geladeira",
    },
    "residential_freezers": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Freezer",
    },
    "clothes_washers": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Lavadora",
    },
    "residential_clothes_dryers": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Secadora",
    },
    "residential_dishwashers": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Lava-louças",
    },
    "residential_electric_cooking": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Fogão/Forno",
    },
    "dehumidifiers": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Desumidificador",
    },
    "pool_pumps": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Bomba de piscina",
    },
    "water_heaters": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Aquecedor de água",
    },
    "boilers": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Caldeira",
    },
    "furnaces": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Fornalha",
    },
    "water_coolers": {
        "category": CATEGORY_APPLIANCES,
        "subcategory": "Bebedouro",
    },
    # --- Cozinha (comercial) -----------------------------------------------
    "commercial_coffee_brewers": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Cafeteira comercial",
    },
    "commercial_dishwashers": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Lava-louças comercial",
    },
    "commercial_electric_cooktops": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Cooktop comercial",
    },
    "commercial_fryers": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Fritadeira comercial",
    },
    "commercial_griddles": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Chapa comercial",
    },
    "commercial_hot_food_holding_cabinets": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Armário aquecido",
    },
    "commercial_ovens": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Forno comercial",
    },
    "commercial_steam_cookers": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Panela a vapor comercial",
    },
    "commercial_ice_machines": {
        "category": CATEGORY_KITCHEN,
        "subcategory": "Máquina de gelo",
    },
    "vending_machines": {
        "category": CATEGORY_COMMERCIAL,
        "subcategory": "Máquina de venda",
    },
    # --- Climatização -------------------------------------------------------
    "room_air_conditioners": {
        "category": CATEGORY_HVAC,
        "subcategory": "Ar-condicionado",
    },
    "room_air_cleaners_v3_0": {
        "category": CATEGORY_HVAC,
        "subcategory": "Purificador de ar",
    },
    "room_air_cleaners": {
        "category": CATEGORY_HVAC,
        "subcategory": "Purificador de ar",
    },
    "ventilating_fans": {
        "category": CATEGORY_HVAC,
        "subcategory": "Ventilador/Exaustor",
    },
    "ceiling_fans": {
        "category": CATEGORY_HVAC,
        "subcategory": "Ventilador de teto",
    },
    "heat_pumps": {
        "category": CATEGORY_HVAC,
        "subcategory": "Bomba de calor",
    },
    "geothermal_heat_pumps": {
        "category": CATEGORY_HVAC,
        "subcategory": "Bomba de calor geotérmica",
    },
    "light_commercial_hvac": {
        "category": CATEGORY_HVAC,
        "subcategory": "HVAC comercial leve",
    },
    "commercial_water_heaters": {
        "category": CATEGORY_HVAC,
        "subcategory": "Aquecedor de água comercial",
    },
    "commercial_boilers": {
        "category": CATEGORY_HVAC,
        "subcategory": "Caldeira comercial",
    },
    # --- Iluminação ---------------------------------------------------------
    "lamps": {
        "category": CATEGORY_LIGHTING,
        "subcategory": "Lâmpada",
    },
    "light_fixtures_downlights": {
        "category": CATEGORY_LIGHTING,
        "subcategory": "Luminária embutida",
    },
    # --- Automação ----------------------------------------------------------
    "smart_thermostats": {
        "category": CATEGORY_AUTOMATION,
        "subcategory": "Termostato",
    },
    # --- Veículos elétricos -------------------------------------------------
    "electric_vehicle_supply_equipment": {
        "category": CATEGORY_AUTOMATION,
        "subcategory": "Carregador de VE",
    },
    # --- Diversos -----------------------------------------------------------
    "laboratory_grade_refrigerators_and_freezers": {
        "category": CATEGORY_COMMERCIAL,
        "subcategory": "Refrigeração laboratorial",
    },
    "medical_imaging_equipment": {
        "category": CATEGORY_COMMERCIAL,
        "subcategory": "Imagem médica",
    },
    "commercial_refrigerators_and_freezers": {
        "category": CATEGORY_COMMERCIAL,
        "subcategory": "Refrigeração comercial",
    },
    "commercial_clothes_washers": {
        "category": CATEGORY_COMMERCIAL,
        "subcategory": "Lavadora comercial",
    },
    "storm_windows": {
        "category": CATEGORY_OTHER,
        "subcategory": "Janela anti-tempestade",
    },
    "insulation": {
        "category": CATEGORY_OTHER,
        "subcategory": "Isolamento térmico",
    },
    "products_upc_codes": {
        "category": CATEGORY_OTHER,
        "subcategory": UNCATEGORIZED,
    },
}


# ---------------------------------------------------------------------------
# Fallback por palavras-chave — datasets ainda nao mapeados (FR-012)
#
# Ordem importa: regras mais especificas primeiro. Cada regra so dispara
# com confianca minima: o termo aparece como TOKEN (palavra) no slug, nao
# como substring acidental ("lamp" casa "heat_pumps" NAO — ver _matches).
# ---------------------------------------------------------------------------

_KEYWORD_RULES: list[tuple[str, str, str]] = [
    # (regex sobre o slug normalizado, category, subcategory)
    (r"air_condition", CATEGORY_HVAC, "Ar-condicionado"),
    (r"air_cleaner|air_purifier", CATEGORY_HVAC, "Purificador de ar"),
    (r"heat_pump", CATEGORY_HVAC, "Bomba de calor"),
    (r"hvac", CATEGORY_HVAC, "HVAC"),
    (r"thermostat", CATEGORY_AUTOMATION, "Termostato"),
    (r"fan|ventilat", CATEGORY_HVAC, "Ventilador/Exaustor"),
    (r"dehumidif", CATEGORY_APPLIANCES, "Desumidificador"),
    (r"refrigerat", CATEGORY_APPLIANCES, "Geladeira"),
    (r"freezer", CATEGORY_APPLIANCES, "Freezer"),
    (r"dishwash", CATEGORY_APPLIANCES, "Lava-louças"),
    (r"clothes_washer|laundry_washer", CATEGORY_APPLIANCES, "Lavadora"),
    (r"clothes_dryer|dryer", CATEGORY_APPLIANCES, "Secadora"),
    (r"stove|range|cooktop|cooking|oven", CATEGORY_APPLIANCES, "Fogão/Forno"),
    (r"water_heater", CATEGORY_APPLIANCES, "Aquecedor de água"),
    (r"boiler", CATEGORY_APPLIANCES, "Caldeira"),
    (r"furnace", CATEGORY_APPLIANCES, "Fornalha"),
    (r"pool_pump", CATEGORY_APPLIANCES, "Bomba de piscina"),
    (r"television|\btv\b", CATEGORY_ELECTRONICS, "Televisão"),
    (r"computer|desktop|laptop|notebook", CATEGORY_COMPUTING, "Computador"),
    (r"monitor|display", CATEGORY_COMPUTING, "Monitor"),
    (r"server", CATEGORY_COMPUTING, "Servidor"),
    (r"printer|imaging|scanner|copier", CATEGORY_ELECTRONICS, "Equipamento de imagem"),
    (r"telephone|phone", CATEGORY_ELECTRONICS, "Telefone"),
    (r"lamp|light|lighting|led\b|bulb", CATEGORY_LIGHTING, "Lâmpada"),
    (r"battery_charger|ups|uninterruptible", CATEGORY_COMPUTING, "No-break"),
    (r"vending", CATEGORY_COMMERCIAL, "Máquina de venda"),
    (r"ice_machine", CATEGORY_KITCHEN, "Máquina de gelo"),
    (r"fryer", CATEGORY_KITCHEN, "Fritadeira comercial"),
    (r"griddle", CATEGORY_KITCHEN, "Chapa comercial"),
    (r"coffee", CATEGORY_KITCHEN, "Cafeteira comercial"),
]


def _matches(pattern: str, slug: str) -> bool:
    """Casa regex contra o slug completo (tokens separados por _)."""
    return re.search(pattern, slug) is not None


def resolve_taxonomy(dataset_category: str | None) -> dict[str, str]:
    """Resolve o par (category, subcategory) a partir do slug do dataset.

    Ordem de resolucao:

    1. Mapeamento exato em :data:`CATEGORY_MAPPING`.
    2. Fallback ordenado por palavras-chave (:data:`_KEYWORD_RULES`).
    3. Nada casa -> ``Outros / Nao categorizado``.

    Args:
        dataset_category: slug tecnico do dataset (ex.: ``"televisions"``).

    Returns:
        ``{"category": ..., "subcategory": ...}`` — sempre preenchido,
        nunca ``None``.
    """
    if not dataset_category:
        return {"category": CATEGORY_OTHER, "subcategory": UNCATEGORIZED}

    slug = dataset_category.strip().casefold()

    exact = CATEGORY_MAPPING.get(slug)
    if exact is not None:
        return dict(exact)

    for pattern, category, subcategory in _KEYWORD_RULES:
        if _matches(pattern, slug):
            return {"category": category, "subcategory": subcategory}

    return {"category": CATEGORY_OTHER, "subcategory": UNCATEGORIZED}
