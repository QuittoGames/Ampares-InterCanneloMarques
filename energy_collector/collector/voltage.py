"""Normalizacao SEGURA de declaracoes de tensao (voltage) das fontes.

Responsabilidade UNICA: interpretar o texto de tensao declarado por uma
fonte (ex.: ``"127 V"``, ``"110/220 V"``, ``"Bivolt"``, ``"100-240 V"``)
em uma estrutura normalizada, SEM alterar o significado fisico.

Regras (spec Brasil-aware — secao 3):

* NUNCA converter tensao. ``220 V`` NAO vira ``110 V``/``127 V`` por
  fator universal; nao ha multiplicacao/divisao de tensao, potencia ou
  energia por tensao.
* ``110 V`` rotulado explicitamente e DISTINTO de ``127 V`` especificado:
  os valores originais ficam em ``min_v``/``max_v`` e o texto verbatim
  em ``raw`` (rastreabilidade).
* Classificacao: ``monovolt`` (um valor declarado), ``bivolt`` (dois
  valores ou palavra-chave explicita), ``range`` (faixa declarada,
  ex.: ``100-240 V``) e ``unknown`` (ausente/nao interpretavel).
* Fonte sem tensao declarada fica ``unknown`` — NUNCA inferida por
  pais, estado, categoria ou marca.

Unidade canonica: volts (V). O valor fisico nunca e alterado — apenas a
notacao e normalizada (ex.: ``"127v"`` -> ``127``; ``"220/110 V"`` ->
``{110, 220}`` como conjunto, sem trocar valores de lugar fisicamente).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any

#: Classificacao possivel da tensao (espelha o CHECK de
#: ``product_source_observation.voltage_kind``).
KIND_UNKNOWN: str = "unknown"
KIND_MONOVOLT: str = "monovolt"
KIND_BIVOLT: str = "bivolt"
KIND_RANGE: str = "range"
VALID_KINDS: frozenset[str] = frozenset(
    {KIND_UNKNOWN, KIND_MONOVOLT, KIND_BIVOLT, KIND_RANGE}
)

#: Faixa fisica plausivel de tensao nominal (V) — filtro contra numeros
#: que nao sao tensao (ex.: ano, codigo). Fora da faixa => ignorado.
_MIN_PLAUSIBLE_V: int = 50
_MAX_PLAUSIBLE_V: int = 600

#: Marcadores de "ausente" — nao carregam tensao declarada.
_NULL_MARKERS: frozenset[str] = frozenset(
    {
        "",
        "-",
        "--",
        "n/a",
        "na",
        "n.d.",
        "nd",
        "none",
        "null",
        "nan",
        "nao informado",
        "não informado",
        "nao declarado",
        "não declarado",
    }
)

#: Palavra-chave de bivolt (pt-BR + en).
_BIVOLT_RE = re.compile(r"bivolt|bi-volt|dual[\s-]?voltage", re.IGNORECASE)

#: Par de valores com separador (``110/220``, ``100-240``, ``110 a 220``).
_PAIR_RE = re.compile(
    r"(\d{2,3})\s*(?:v\s*)?"
    r"([/,\-–—~]|\s+a\s+|\s+to\s+)\s*"
    r"(\d{2,3})\s*(?:v)?",
    re.IGNORECASE,
)

#: Valor unico (``127 V``, ``220v``).
_SINGLE_RE = re.compile(r"(\d{2,3})\s*v?\b", re.IGNORECASE)

#: Separadores que indicam FAIXA (range) e nao bivolt.
_RANGE_SEPARATORS: frozenset[str] = frozenset({"-", "–", "—", "~", " a ", " to "})


@dataclass(frozen=True, slots=True)
class VoltageSpec:
    """Declaracao de tensao normalizada (proveniencia de fonte).

    Attributes:
        raw: Texto original aparado (verbatim), preservado para auditoria.
            ``None`` quando a fonte nao declarou tensao.
        kind: ``unknown``/``monovolt``/``bivolt``/``range``.
        min_v: Menor valor declarado em volts (``None`` se desconhecido).
        max_v: Maior valor declarado em volts (``None`` se desconhecido).
            Para ``monovolt``: ``min_v == max_v``.
    """

    raw: str | None
    kind: str
    min_v: Decimal | None
    max_v: Decimal | None


def _as_decimal(value: int) -> Decimal | None:
    if not (_MIN_PLAUSIBLE_V <= value <= _MAX_PLAUSIBLE_V):
        return None
    try:
        return Decimal(value)
    except InvalidOperation:  # pragma: no cover - defensivo
        return None


def parse_voltage(value: Any) -> VoltageSpec:
    """Interpreta uma declaracao de tensao sem alterar o valor fisico.

    Exemplos:

    * ``"127 V"`` -> monovolt 127/127
    * ``"110 V"`` -> monovolt 110/110 (NUNCA vira 127)
    * ``"110/220 V"`` / ``"Bivolt"`` -> bivolt
    * ``"100-240 V"`` -> range 100..240
    * ``None`` / ``""`` / ``"N/A"`` -> unknown

    Returns:
        ``VoltageSpec`` sempre — nunca levanta excecao por entrada ruim.
    """
    if value is None:
        return VoltageSpec(None, KIND_UNKNOWN, None, None)
    text = str(value).strip()
    if text.lower() in _NULL_MARKERS:
        return VoltageSpec(None, KIND_UNKNOWN, None, None)

    raw = text
    declared_bivolt = bool(_BIVOLT_RE.search(text))

    pair = _PAIR_RE.search(text)
    if pair:
        first = _as_decimal(int(pair.group(1)))
        # group(2) e o SEPARADOR ('/', '-', ...); group(3) e o 2o valor.
        second = _as_decimal(int(pair.group(3)))
        if first is not None and second is not None:
            low, high = sorted((first, second))
            separator = pair.group(2).lower()
            if separator in _RANGE_SEPARATORS and not declared_bivolt:
                return VoltageSpec(raw, KIND_RANGE, low, high)
            return VoltageSpec(raw, KIND_BIVOLT, low, high)

    single = _SINGLE_RE.search(text)
    if single:
        value_v = _as_decimal(int(single.group(1)))
        if value_v is not None:
            if declared_bivolt:
                return VoltageSpec(raw, KIND_BIVOLT, value_v, value_v)
            return VoltageSpec(raw, KIND_MONOVOLT, value_v, value_v)

    if declared_bivolt:
        # Bivolt declarado textualmente sem numeros legiveis: tipo confiavel,
        # valores desconhecidos (nada e inventado).
        return VoltageSpec(raw, KIND_BIVOLT, None, None)

    return VoltageSpec(raw, KIND_UNKNOWN, None, None)


__all__ = [
    "KIND_BIVOLT",
    "KIND_MONOVOLT",
    "KIND_RANGE",
    "KIND_UNKNOWN",
    "VALID_KINDS",
    "VoltageSpec",
    "parse_voltage",
]
