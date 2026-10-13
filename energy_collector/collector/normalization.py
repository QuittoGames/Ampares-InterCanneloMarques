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
* Tensao: declaracao de tensao e extraida como PROVENIENCIA (raca
  ``collector.voltage``) — valor/rotulo preservados (110 V != 127 V),
  nunca convertidos e nunca inferidos por pais/estado.
* SEM formulas de derivados aqui: horas equivalentes, energia diaria/
  mensal, custo, tarifa e consumo de standby pertencem ao motor de
  calculo Java (Banco de Formulas AMPARES, spec secoes 5 e formula bank
  final). O coletor entrega apenas dado bruto normalizado + unidades —
  uma segunda engine de formulas em Python criaria divergencia.
* Rastreabilidade: SOURCE DATA (valores brutos, unidade/periodo
  originais em ``raw_energy_value``/``raw_energy_unit``) e preservado em
  :class:`collector.models.NormalizedProduct`/``product_source_observation``.
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
from .voltage import KIND_UNKNOWN, VoltageSpec, parse_voltage

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
#: Campos semanais/mensais (``_wk``/``_month``) NAO sao equivalentes —
#: casar ``tec_kwh_wk`` como anual falsifica o valor em ~52x (bug real
#: do dataset de imaging: TEC semanal 0.6 kWh/wk virava 0.6 kWh/ano).
ANNUAL_FIELD_EQUIVALENTS: tuple[str, ...] = (
    "annual_energy_kwh",
    "annual_energy_use_kwh",
    "annual_energy_consumption_kwh",
    "annual_consumption_kwh",
    "annual_energy_use_kwh_year",
    "annual_energy_use_kwh_yr",
    "reported_annual_energy_consumption_kwh",
    "tec_of_model_kwh",
    "typical_electricity_consumption_tec_kwh_yr",
    "kwh_year",
    "kwh_yr",
)

#: Tokens que identificam coluna de potencia em MODO DE ECONOMIA/DESLIGADO
#: — NUNCA representam a potencia media de uso. Excluidos do fallback
#: generico (bug real: ``power_in_sleep_w`` = 0.92W do KIP 700 foi
#: gravado como ``avg_power_w``; a potencia real de uso e 600-1500W e
#: simplesmente NAO e publicada pelo dataset de imaging).
POWER_MODE_EXCLUDED_TOKENS: tuple[str, ...] = (
    "standby",
    "idle",
    "sleep",
    "off",
    "shutdown",
    "poweroff",
    "power_off",
)

#: Tokens que identificam coluna de energia em periodo MENOR que ano
#: (semanal/mensal) — NAO sao equivalentes anuais.
ANNUAL_PERIOD_EXCLUDED_TOKENS: tuple[str, ...] = (
    "_wk",
    "_week",
    "_weekly",
    "per_week",
    "_mo",
    "_month",
    "_monthly",
    "per_month",
    "_day",
    "_daily",
    "per_day",
)

#: Regex generica de fallback para datasets desconhecidos (FR-012).
POWER_RE = re.compile(r"[Pp]ower|[Ww]att|[Ww]atts", re.IGNORECASE)
ANNUAL_RE = re.compile(
    r"annual.*kwh|kwh_yr|kwh_year|annual_energy|consumption.*kwh|tec_of_model_kwh|annual_consumption",
    re.IGNORECASE,
)

#: Equivalencias obvias de nomes de coluna de POTENCIA EM STANDBY (W).
#: Explicitas e priorizadas — casam apenas campos de standby/idle.
STANDBY_FIELD_EQUIVALENTS: tuple[str, ...] = (
    "standby_power_watts",
    "power_consumption_in_standby_mode_watts",
    "standby_power_w",
    "standby_watts",
    "power_standby_watts",
    "standby_mode_watts",
)

#: Regex para potencia em standby (usada so para datasets desconhecidos).
STANDBY_RE = re.compile(r"standby|idle", re.IGNORECASE)

#: Equivalencias obvias de coluna de TENSAO declarada (V). Apenas chaves
#: explicitas — a tensao NUNCA e inferida por regex solta (risco de casar
#: anos/codigos) nem por pais/estado.
VOLTAGE_FIELD_EQUIVALENTS: tuple[str, ...] = (
    "voltage",
    "voltage_v",
    "rated_voltage",
    "voltage_rating",
    "tensao",
    "tensao_v",
    "tensao_nominal",
    "voltagem",
)

_PREFIX_RE = re.compile(r"energy star certified", re.IGNORECASE)


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


def _matches_any_token(key: str, tokens: tuple[str, ...]) -> bool:
    """Verifica se a coluna casa algum token (case-insensitive)."""
    lowered = key.casefold()
    return any(token in lowered for token in tokens)


def _match_power_key(raw: dict[str, Any]) -> str | None:
    """Reconhece a coluna de potencia de forma segura (equivalencias obvias).

    Prioriza equivalencias explícitas; cai na regex generica so para
    datasets desconhecidos (FR-012). Colunas de modo de economia
    (standby/idle/sleep/off) NUNCA representam a potencia media de uso e
    sao excluidas — ``power_in_sleep_w`` (0.92W) nao e a potencia de uma
    impressora de 1500W.
    """
    for equiv in POWER_FIELD_EQUIVALENTS:
        if equiv in raw:
            return equiv
    # Fallback: preferir colunas com "on_mode"/"rated" sobre modos de
    # economia/desligado (que nunca sao a potencia media de uso).
    keys = [k for k in raw if POWER_RE.search(k)]
    if not keys:
        return None
    preferred = [
        k for k in keys if not _matches_any_token(k, POWER_MODE_EXCLUDED_TOKENS)
    ]
    return (preferred or keys)[0]


def _match_standby_key(raw: dict[str, Any]) -> str | None:
    """Reconhece a coluna de potencia em standby (W) de forma segura.

    Diferente de :func:`_match_power_key`, AQUI queremos justamente os
    campos de standby/idle. Prioriza equivalencias explicitas; cai na
    regex generica so para datasets desconhecidos.
    """
    for equiv in STANDBY_FIELD_EQUIVALENTS:
        if equiv in raw:
            return equiv
    keys = [k for k in raw if STANDBY_RE.search(k)]
    if not keys:
        return None
    # Entre varios matches, prefere os que dizem respeito a watts.
    preferred = [k for k in keys if "watt" in k.lower()]
    return (preferred or keys)[0]


def _match_annual_key(raw: dict[str, Any]) -> str | None:
    """Reconhece a coluna de energia anual de forma segura (equivalencias).

    Colunas de periodo menor que ano (``_wk``/``_month``/``_day``) sao
    EXCLUIDAS do fallback — casar ``tec_kwh_wk`` (semanal) como anual
    falsifica o valor em ~52x.
    """
    for equiv in ANNUAL_FIELD_EQUIVALENTS:
        if equiv in raw:
            return equiv
    key = _first_matching_key(raw, ANNUAL_RE)
    if key is not None and _matches_any_token(key, ANNUAL_PERIOD_EXCLUDED_TOKENS):
        logger.debug("Coluna anual %r e de periodo menor que ano — descartada", key)
        return None
    return key


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
) -> tuple[Decimal | None, Decimal | None, Decimal | None]:
    """Extrai ``(avg_power_w, annual_energy_kwh, standby_power_w)`` brutos (SOURCE).

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
        standby_key = cfg.get("standby")
        standby = (
            _to_decimal(raw.get(standby_key), "standby_power_w")
            if standby_key
            else None
        )
        return power, annual, standby

    power_key = _match_power_key(raw)
    annual_key = _match_annual_key(raw)
    standby_key = _match_standby_key(raw)
    power = _to_decimal(raw.get(power_key), "avg_power_w") if power_key else None
    annual = (
        _to_decimal(raw.get(annual_key), "annual_energy_kwh") if annual_key else None
    )
    standby = (
        _to_decimal(raw.get(standby_key), "standby_power_w") if standby_key else None
    )
    return power, annual, standby


def _extract_source_id(raw: dict[str, Any], model: str | None) -> str | None:
    """Cadeia de identificador estavel (SOURCE DATA) — preservada."""
    return (
        _as_clean_str(raw.get("pd_id"))
        or _as_clean_str(raw.get("energy_star_model_identifier"))
        or _as_clean_str(raw.get("model_number"))
        or model
    )


def _extract_voltage(
    raw: dict[str, Any], cfg: dict[str, str | None] | None
) -> VoltageSpec:
    """Extrai a declaracao de tensao como proveniencia (secao 3 da spec).

    Mapeamento verificado (``cfg["voltage"]``) tem prioridade; senao,
    equivalencias obvias de nome. Ausente/nao interpretavel -> ``unknown``
    (nunca inferido por pais, estado, categoria ou marca).
    """
    key = cfg.get("voltage") if cfg is not None else None
    if not key:
        for equiv in VOLTAGE_FIELD_EQUIVALENTS:
            if equiv in raw:
                key = equiv
                break
    if not key:
        return VoltageSpec(None, KIND_UNKNOWN, None, None)
    return parse_voltage(raw.get(key))


# ---------------------------------------------------------------------------
# Normalizacao
# ---------------------------------------------------------------------------


def normalize(
    raw: dict[str, Any],
    dataset_id: str,
    category: str,
    *,
    source: str = SOURCE_NAME,
) -> Product | None:
    """Normaliza um registro bruto em :class:`Product` (contrato de escrita).

    Mantido como a funcao principal do pipeline existente: retorna o
    :class:`Product` canonico que vai ao banco. Para rastreabilidade
    completa (valores brutos da fonte), use :func:`normalize_record`.

    Args:
        raw: Linha crua do dataset Socrata.
        dataset_id: ID 4x4 de origem (mapeamento verificado quando
            conhecido, heuristica caso contrario).
        category: Categoria logica do dataset (alimenta ``Product.category``).
        source: Identificador da fonte (atribuido a ``Product.source``).
            Default ``SOURCE_NAME`` (``"ENERGY STAR"``) preserva
            bit-a-bit os UUIDs existentes. Fontes novas (WattSimple,
            INMETRO) passam seu proprio codigo (ex.: ``"WATTSIMPLE"``).

    Returns:
        ``Product`` ou ``None`` sem identificacao minima — o chamador
        contabiliza como descartado (com log).
    """
    record = normalize_record(
        raw=raw, dataset_id=dataset_id, category=category, source=source
    )
    return record.product if record is not None else None


def normalize_record(
    raw: dict[str, Any],
    dataset_id: str,
    category: str,
    *,
    source: str = SOURCE_NAME,
) -> NormalizedProduct | None:
    """Normaliza um registro bruto preservando SOURCE DATA da fonte.

    Esta e a entrada rica: retorna :class:`NormalizedProduct` com o
    ``product`` canonico (escrita) e os valores brutos da API (``raw_*``,
    unidade/periodo originais). NENHUM valor derivado e calculado —
    custo, tarifa, horas e perfis de uso pertencem ao motor Java.

    Args:
        raw: Linha crua do dataset Socrata.
        dataset_id: ID 4x4 de origem.
        category: Categoria logica do dataset.
        source: Identificador da fonte (atribuido a ``Product.source``).
            Default ``SOURCE_NAME`` para preservar bit-a-bit os UUIDs
            do pipeline ENERGY STAR legado.

    Returns:
        ``NormalizedProduct`` ou ``None`` sem identificacao minima.
    """
    cfg = KNOWN_DATASETS.get(dataset_id)

    brand, model = _extract_brand_model(raw, cfg)
    raw_power, raw_annual, raw_standby = _extract_energy(raw, cfg)
    voltage = _extract_voltage(raw, cfg)

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
        standby_power_w=raw_standby,
        source=source,  # parametrizado (PR 1+); default = SOURCE_NAME = "ENERGY STAR"
        source_id=source_id,
        dataset_category=category,
        dataset_id=dataset_id,
        # Proveniencia de tensao/energia (secoes 3 e 5) — nunca em `product`.
        voltage_raw=voltage.raw,
        voltage_kind=voltage.kind,
        voltage_min_v=voltage.min_v,
        voltage_max_v=voltage.max_v,
        raw_energy_value=raw_annual,
        raw_energy_unit="kWh/year" if raw_annual is not None else None,
    )

    return NormalizedProduct(
        product=product,
        raw_power=raw_power,
        raw_annual_energy=raw_annual,
        standby_power_w=raw_standby,
    )
