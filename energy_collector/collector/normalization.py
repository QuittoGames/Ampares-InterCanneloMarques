"""Normalizacao segura e deterministica de registros brutos Socrata.

Responsabilidade UNICA: transformar dados crus da API em dados compativeis
com o modelo do software, de forma rapida, deterministica, reproduzivel e
testavel. NAO e uma camada de IA — nao classifica semanticamente, nao
inventa valores, nao infere perfil de uso.

Decisoes:

* Tipos: valores numericos (``"150"``, ``"150.0"``, ``150``, ``150.0``)
  sao convertidos para ``Decimal`` consistente. Dinheiro/energia usam
  ``Decimal`` (precisao). ``"100,5"`` (virgula decimal) e aceito quando a
  conversao e claramente segura.
* Vazios: ``""``, ``null``, ``None``, ``"null"``, ``"NULL"`` -> ``None``.
* Strings: whitespace colapsado; vazias -> ``None``.
* Campos de energia: equivalencias OBVIAS de nomes sao reconhecidas
  (ex.: ``power``/``watts``/``power_watts``/``rated_power_watts``;
  ``annual_energy_kwh``/``annual_energy_use_kwh``/``annual_consumption``).
  Se um campo nao puder ser interpretado com seguranca -> ``None``.
* Derivados: calculos puramente matematicos a partir dos dados existentes
  (horas equivalentes, energia diaria, custo). Nunca inventados; tarifa
  sempre explicita (config/parametro), nunca arbitraria.
* Rastreabilidade: SOURCE DATA (valores brutos) e DERIVED DATA (calculos)
  sao separados em :class:`collector.models.NormalizedProduct`.
* O registro nunca e descartado por metrica ausente/ruim — apenas o campo
  vira ``None``. Descarte so sem identificacao minima (sem ``source_id``
  nem marca+modelo).
"""

from __future__ import annotations

import logging
import math
import re
from decimal import Decimal, InvalidOperation
from typing import Any

from .config import KNOWN_DATASETS
from .models import NAME_MAX, SOURCE_NAME, TEXT_MAX, NormalizedProduct, Product
from .taxonomy import resolve_taxonomy

logger = logging.getLogger(__name__)

#: Equivalencias obvias de nomes de coluna de POTENCIA (potencia media em W).
#: Ordem importa: nomes mais especificos primeiro (evita casar standby).
POWER_FIELD_EQUIVALENTS: tuple[str, ...] = (
    "rated_power_watts",
    "power_watts",
    "watts",
    "power",
    "avg_power_w",
    "power_consumption_in_on_mode_watts",
)

#: Equivalencias obvias de nomes de coluna de ENERGIA ANUAL (kWh/ano).
ANNUAL_FIELD_EQUIVALENTS: tuple[str, ...] = (
    "annual_energy_kwh",
    "annual_energy_use_kwh",
    "annual_energy_consumption_kwh",
    "annual_consumption_kwh",
    "annual_energy_use_kwh_year",
    "annual_energy_use_kwh_yr",
    "reported_annual_energy_consumption_kwh",
    "tec_of_model_kwh",
    "kwh_year",
    "kwh_yr",
)

#: Regex generica de fallback para datasets desconhecidos (FR-012).
POWER_RE = re.compile(r"[Pp]ower|[Ww]att|[Ww]atts", re.IGNORECASE)
ANNUAL_RE = re.compile(
    r"annual.*kwh|kwh_yr|kwh_year|annual_energy|consumption.*kwh|tec_of_model_kwh|annual_consumption",
    re.IGNORECASE,
)

_PREFIX_RE = re.compile(r"energy star certified", re.IGNORECASE)

#: Dias em um ano (base para derivados diarios).
_DAYS_PER_YEAR = Decimal("365")


def slugify_category(dataset_name: str) -> str:
    """Deriva categoria logica do titulo do dataset (FR-012).

    "ENERGY STAR Certified Residential Dishwashers" -> "residential_dishwashers".
    """
    name = _PREFIX_RE.sub("", dataset_name)
    slug = re.sub(r"[^a-z0-9]+", "_", name.casefold()).strip("_")
    return slug or "uncategorized"


# ---------------------------------------------------------------------------
# Conversores seguros e deterministicos
# ---------------------------------------------------------------------------


def _as_clean_str(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _truncate(text: str | None, limit: int, field: str) -> str | None:
    """Trunca ao limite do contrato com log (nunca erro de banco)."""
    if text is not None and len(text) > limit:
        logger.debug(
            "Truncando %s (%d->%d chars): %r", field, len(text), limit, text[:40]
        )
        return text[:limit]
    return text


def _normalize_empty(value: Any) -> Any:
    """Normaliza representacoes de vazio (``""``, ``"null"``, etc.) -> None."""
    if value is None:
        return None
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped or stripped.lower() in ("null", "none", "nan"):
            return None
        return stripped
    return value


def _to_decimal(value: Any, field: str) -> Decimal | None:
    """Coercao defensiva para NUMERIC (Decimal consistente).

    Aceita ``"100"``, ``"100.5"``, ``100``, ``100.0`` e ``"100,5"``
    (virgula decimal, conversao segura). None/vazio/nao-numerico/NaN/
    infinito/negativo -> None (R6). O registro nunca e descartado por
    metrica ruim — apenas o campo e anulado com log.
    """
    cleaned = _normalize_empty(value)
    if cleaned is None:
        return None
    # Conversao segura de virgula decimal ("100,5") — NAO troca separador
    # de milhar ("1,000" seria ambíguo e nao e tratado como seguro).
    if isinstance(cleaned, str) and "," in cleaned and "." not in cleaned:
        candidate = cleaned.replace(",", ".")
        try:
            return _to_decimal(candidate, field)
        except (ValueError, InvalidOperation):
            logger.debug("Metrica nao-numerica %s=%r -> NULL", field, repr(value)[:40])
            return None

    try:
        number = float(cleaned)
    except (TypeError, ValueError):
        logger.debug("Metrica nao-numerica %s=%r -> NULL", field, repr(value)[:40])
        return None
    if not math.isfinite(number):
        logger.debug("Metrica nao-finita %s=%r -> NULL", field, repr(value)[:40])
        return None
    if number < 0:
        logger.debug("Metrica negativa %s=%r -> NULL", field, repr(value)[:40])
        return None
    try:
        return Decimal(str(number))
    except InvalidOperation:
        logger.debug("Metrica invalida %s=%r -> NULL", field, repr(value)[:40])
        return None


def _first_matching_key(raw: dict[str, Any], pattern: re.Pattern[str]) -> str | None:
    for key in raw:
        if pattern.search(key):
            return key
    return None


def _match_power_key(raw: dict[str, Any]) -> str | None:
    """Reconhece a coluna de potencia de forma segura (equivalencias obvias).

    Prioriza equivalencias explícitas; cai na regex generica so para
    datasets desconhecidos (FR-012). Evita campos de standby/idle que nao
    representam a potencia media de uso.
    """
    for equiv in POWER_FIELD_EQUIVALENTS:
        if equiv in raw:
            return equiv
    # Fallback: preferir colunas com "on_mode"/"rated" sobre standby/idle.
    keys = [k for k in raw if POWER_RE.search(k)]
    if not keys:
        return None
    preferred = [k for k in keys if "standby" not in k and "idle" not in k]
    return (preferred or keys)[0]


def _match_annual_key(raw: dict[str, Any]) -> str | None:
    """Reconhece a coluna de energia anual de forma segura (equivalencias)."""
    for equiv in ANNUAL_FIELD_EQUIVALENTS:
        if equiv in raw:
            return equiv
    return _first_matching_key(raw, ANNUAL_RE)


# ---------------------------------------------------------------------------
# Campos canonicos (SOURCE DATA)
# ---------------------------------------------------------------------------


def _extract_brand_model(
    raw: dict[str, Any], cfg: dict[str, str | None] | None
) -> tuple[str | None, str | None]:
    """Extrai marca/modelo (mapeamento verificado ou heuristica generica)."""
    if cfg is not None:
        brand = _as_clean_str(raw.get(cfg["brand"])) if cfg["brand"] else None
        model = _as_clean_str(raw.get(cfg["model"])) if cfg["model"] else None
        return brand, model
    # Heuristica generica (FR-012): so chaves realmente presentes.
    brand = _as_clean_str(raw.get("brand_name")) or _as_clean_str(
        raw.get("energy_star_partner")
    )
    model = _as_clean_str(raw.get("model_name")) or _as_clean_str(
        raw.get("model_number")
    )
    return brand, model


def _extract_energy(
    raw: dict[str, Any], cfg: dict[str, str | None] | None
) -> tuple[Decimal | None, Decimal | None]:
    """Extrai ``(avg_power_w, annual_energy_kwh)`` brutos (SOURCE).

    Usa mapeamento verificado quando conhecido; equivalencias obvias e
    regex generica para desconhecidos. Campos nao interpretaveis -> None.
    """
    if cfg is not None:
        power = (
            _to_decimal(raw.get(cfg["power"]), "avg_power_w") if cfg["power"] else None
        )
        annual = (
            _to_decimal(raw.get(cfg["annual"]), "annual_energy_kwh")
            if cfg["annual"]
            else None
        )
        return power, annual

    power_key = _match_power_key(raw)
    annual_key = _match_annual_key(raw)
    power = _to_decimal(raw.get(power_key), "avg_power_w") if power_key else None
    annual = (
        _to_decimal(raw.get(annual_key), "annual_energy_kwh") if annual_key else None
    )
    return power, annual


def _extract_source_id(raw: dict[str, Any], model: str | None) -> str | None:
    """Cadeia de identificador estavel (SOURCE DATA) — preservada."""
    return (
        _as_clean_str(raw.get("pd_id"))
        or _as_clean_str(raw.get("energy_star_model_identifier"))
        or _as_clean_str(raw.get("model_number"))
        or model
    )


# ---------------------------------------------------------------------------
# Calculos derivados (DERIVED DATA) — matematica deterministica
# ---------------------------------------------------------------------------


def _safe_divide(
    numerator: Decimal | None, denominator: Decimal | None
) -> Decimal | None:
    """Divisao segura: ``None`` quando o denominador e zero ou ausente."""
    if numerator is None or denominator is None or denominator == 0:
        return None
    try:
        return numerator / denominator
    except (InvalidOperation, ZeroDivisionError):
        return None


def compute_equivalent_hours_year(
    avg_power_w: Decimal | None, annual_energy_kwh: Decimal | None
) -> Decimal | None:
    """Horas equivalentes por ano: ``H_eq = 1000 * E_year / P``.

    Onde ``E_year`` em kWh e ``P`` em watts. Derivado apenas quando ambos
    existem e ``P > 0`` (sem divisao por zero).
    """
    if avg_power_w is None or annual_energy_kwh is None:
        return None
    return _safe_divide(Decimal("1000") * annual_energy_kwh, avg_power_w)


def compute_equivalent_hours_year_day(
    equivalent_hours_year: Decimal | None,
) -> Decimal | None:
    """Horas equivalentes por dia: ``H_eq_day = H_eq / 365``."""
    return _safe_divide(equivalent_hours_year, _DAYS_PER_YEAR)


def compute_estimated_daily_energy(annual_energy_kwh: Decimal | None) -> Decimal | None:
    """Energia diaria estimada: ``E_day = E_year / 365``."""
    return _safe_divide(annual_energy_kwh, _DAYS_PER_YEAR)


def compute_estimated_cost(
    annual_energy_kwh: Decimal | None, tariff_per_kwh: Decimal | None
) -> Decimal | None:
    """Custo anual estimado: ``C = E_year * T``.

    A tarifa ``T`` (moeda/kWh) DEVE vir explicita (config/parametro/banco/
    servico externo) — nunca e assumida arbitrariamente aqui.
    """
    if annual_energy_kwh is None or tariff_per_kwh is None:
        return None
    return annual_energy_kwh * tariff_per_kwh


def compute_derived(
    avg_power_w: Decimal | None,
    annual_energy_kwh: Decimal | None,
    tariff_per_kwh: Decimal | None = None,
) -> dict[str, Decimal | None]:
    """Calcula todos os derivados deterministicos de uma vez.

    Retorna dict com as chaves dos campos DERIVED DATA de
    :class:`NormalizedProduct`. Nenhum valor inventado: ausentes ou
    divisao por zero -> ``None``.
    """
    equivalent_hours_year = compute_equivalent_hours_year(
        avg_power_w, annual_energy_kwh
    )
    return {
        "equivalent_hours_year": equivalent_hours_year,
        "equivalent_hours_year_day": compute_equivalent_hours_year_day(
            equivalent_hours_year
        ),
        "estimated_daily_energy_kwh": compute_estimated_daily_energy(annual_energy_kwh),
        "estimated_cost": compute_estimated_cost(annual_energy_kwh, tariff_per_kwh),
    }


# ---------------------------------------------------------------------------
# Normalizacao
# ---------------------------------------------------------------------------


def normalize(raw: dict[str, Any], dataset_id: str, category: str) -> Product | None:
    """Normaliza um registro bruto em :class:`Product` (contrato de escrita).

    Mantido como a funcao principal do pipeline existente: retorna o
    :class:`Product` canonico que vai ao banco. Para rastreabilidade
    completa (SOURCE + DERIVED), use :func:`normalize_record`.

    Args:
        raw: Linha crua do dataset Socrata.
        dataset_id: ID 4x4 de origem (mapeamento verificado quando
            conhecido, heuristica caso contrario).
        category: Categoria logica do dataset (alimenta ``Product.category``).

    Returns:
        ``Product`` ou ``None`` sem identificacao minima — o chamador
        contabiliza como descartado (com log).
    """
    record = normalize_record(raw=raw, dataset_id=dataset_id, category=category)
    return record.product if record is not None else None


def normalize_record(
    raw: dict[str, Any],
    dataset_id: str,
    category: str,
    *,
    tariff_per_kwh: Decimal | None = None,
) -> NormalizedProduct | None:
    """Normaliza um registro bruto, separando SOURCE e DERIVED DATA.

    Esta e a entrada rica: retorna :class:`NormalizedProduct` com o
    ``product`` canonico (escrita), os valores brutos da API (``raw_*``)
    e os derivados calculados (``equivalent_*`` / ``estimated_*``).

    Args:
        raw: Linha crua do dataset Socrata.
        dataset_id: ID 4x4 de origem.
        category: Categoria logica do dataset.
        tariff_per_kwh: Tarifa (moeda/kWh) explicita para o custo derivado.
            ``None`` (padrao) -> custo derivado fica ``None``.

    Returns:
        ``NormalizedProduct`` ou ``None`` sem identificacao minima.
    """
    cfg = KNOWN_DATASETS.get(dataset_id)

    brand, model = _extract_brand_model(raw, cfg)
    raw_power, raw_annual = _extract_energy(raw, cfg)

    source_id = _extract_source_id(raw, model)

    # Identificacao minima: sem source_id E sem marca+modelo => descarte.
    if not source_id and not (brand and model):
        logger.debug(
            "Registro descartado (sem identificacao estavel): chaves=%s",
            sorted(raw.keys())[:12],
        )
        return None

    name_parts = [part for part in (brand, model) if part]
    name = " ".join(name_parts) if name_parts else source_id

    # Taxonomia global: o NOME TECNICO do dataset nunca vira a categoria
    # final — ele apenas alimenta o mapeamento (e a rastreabilidade).
    taxonomy = resolve_taxonomy(category)

    product = Product(
        name=_truncate(name, NAME_MAX, "name"),
        brand=_truncate(brand, TEXT_MAX, "brand"),
        model=_truncate(model, TEXT_MAX, "model"),
        category=_truncate(taxonomy["category"], TEXT_MAX, "category") or "Outros",
        subcategory=_truncate(taxonomy["subcategory"], TEXT_MAX, "subcategory")
        or "Não categorizado",
        avg_power_w=raw_power,
        annual_energy_kwh=raw_annual,
        source=SOURCE_NAME,
        source_id=source_id,
        dataset_category=category,
        dataset_id=dataset_id,
    )

    derived = compute_derived(raw_power, raw_annual, tariff_per_kwh)

    return NormalizedProduct(
        product=product,
        raw_power=raw_power,
        raw_annual_energy=raw_annual,
        tariff_per_kwh=tariff_per_kwh,
        **derived,
    )
