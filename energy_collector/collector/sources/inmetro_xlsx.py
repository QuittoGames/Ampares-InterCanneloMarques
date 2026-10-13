"""Transporte REAL da fonte INMETRO/PBE: XLSX oficial publicado.

Evidencia verificada (out/2026):

* O sistema interativo PBE (``pbe.inmetro.gov.br``) e uma aplicacao web
  sem API publica REST conhecida (secao 2 da spec: NAO se inventa
  endpoint).
* O INMETRO publica, por categoria, tabelas XLSX oficiais com TODOS os
  produtos aprovados no PBE. Refrigeradores e assemelhados:
  ``http://www.inmetro.gov.br/CONSUMIDOR/pbe/refrigeradores.asp``
  -> link ``Tabela_Inmetro_Refrigeradores_e_Assemelhados.xlsx``
  (versao do arquivo informada no proprio XLSX, ex.: 12/11/2021).
* Estrutura verificada (linhas de cabecalho em multi-nivel):
  ``FORNECEDOR | MARCA | MODELO | TIPO DE PRODUTO | SISTEMA DE DEGELO |
  AGENTE DE EXPANSÃO DA ESPUMA | Nº DE REGISTRO | VOLUME INTERNO (l) |
  CONSUMO DE ENERGIA (kWh/mês) -> 127 V / 220 V / VA`` e faixas de
  classificacao (Padrao 2015/2022) por tensao.

Regras de ingestao (secoes 3 e 5 da spec):

* O consumo e declarado POR TENSAO (colunas 127 V e 220 V distintas).
  Cada (modelo, tensao) com consumo declarado vira UMA observacao com a
  tensao original — NUNCA se converte consumo entre tensoes e NUNCA se
  aplica fator de tensao.
* A coluna ``VA`` (potencia aparente em volt-ampere) NAO e energia em
  kWh/mes: e IGNORADA (unidade incompativel; nao se mistura W/VA com
  kWh).
* ``Nº DE REGISTRO`` e o numero do CERTIFICADO e pode cobrir varios
  modelos (verificado na tabela) — NAO e usado como identidade; a
  identidade por tensao e ``marca|modelo|tensao``. O registro segue no
  registro bruto em memoria (rastreabilidade).
* Modelos sem consumo declarado em nenhuma tensao nao geram registros.

O parser usa SOMENTE stdlib (zipfile + ElementTree) — XLSX e um ZIP de
XML (OOXML). Leitura em memoria: bytes injetados (testes), arquivo
local ou URL oficial.
"""

from __future__ import annotations

import logging
import re
import zipfile
from io import BytesIO
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET

import requests

from .inmetro import DATASET_ID

logger = logging.getLogger(__name__)

#: Codigo estavel da fonte (mesmo codigo do adapter INMETRO).
SOURCE_CODE: str = "INMETRO"

#: URL oficial REAL da tabela XLSX de refrigeradores (pagina .asp -> link).
INMETRO_XLSX_URL: str = (
    "http://www.inmetro.gov.br/CONSUMIDOR/pbe/"
    "Tabela_Inmetro_Refrigeradores_e_Assemelhados.xlsx"
)

_NS = {
    "m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}

#: Tensoes elegiveis nas sub-colunas de CONSUMO DE ENERGIA (kWh/mes).
#: ``VA`` (volt-ampere, potencia aparente) e deliberadamente EXCLUIDA.
_INGESTIBLE_VOLTAGES: dict[str, str] = {
    "127 v": "127 V",
    "220 v": "220 V",
}

#: Coluna(s) de faixa de classificacao preferidas (mais recente primeiro).
_CLASS_PREFERENCE: tuple[str, ...] = (
    "padrão 2022",
    "padrão 2015",
    "padrao 2022",
    "padrao 2015",
)


def _norm(text: str | None) -> str:
    """Colapso de whitespace + casefold para casar cabecalhos."""
    return " ".join(str(text or "").split()).casefold()


def _cell_text(cell: Any, shared: list[str]) -> str:
    """Texto de uma celula OOXML (shared string, inline ou numero)."""
    cell_type = cell.get("t")
    if cell_type == "s":
        value = cell.find("m:v", _NS)
        if value is not None and value.text is not None:
            return shared[int(value.text)]
        return ""
    inline = cell.find("m:is", _NS)
    if inline is not None:
        return "".join(t.text or "" for t in inline.iter(f"{{{_NS['m']}}}t"))
    value = cell.find("m:v", _NS)
    return value.text if value is not None and value.text is not None else ""


def _column_letter(cell_ref: str) -> str:
    return re.match(r"([A-Z]+)", cell_ref).group(1)


def _sheet_rows(zipped: zipfile.ZipFile) -> list[dict[str, str]]:
    """Linhas da primeira planilha como ``{letra: texto}``."""
    shared: list[str] = []
    if "xl/sharedStrings.xml" in zipped.namelist():
        root = ET.fromstring(zipped.read("xl/sharedStrings.xml"))
        for item in root.findall("m:si", _NS):
            shared.append("".join(t.text or "" for t in item.iter(f"{{{_NS['m']}}}t")))

    sheet_path = next(
        name
        for name in zipped.namelist()
        if re.fullmatch(r"xl/worksheets/sheet1?\.xml", name)
    )
    sheet = ET.fromstring(zipped.read(sheet_path))
    rows: list[dict[str, str]] = []
    for row in sheet.iter(f"{{{_NS['m']}}}row"):
        cells: dict[str, str] = {}
        for cell in row.iter(f"{{{_NS['m']}}}c"):
            cells[_column_letter(cell.get("r", ""))] = _cell_text(cell, shared)
        rows.append(cells)
    return rows


class InmetroXlsxClient:
    """Le a tabela XLSX oficial e emite linhas achatadas por tenso.

    Implementa :class:`SourceClient` (mesmo contrato do ``InmetroClient``
    CSV): ``fetch_page``/``count``/``discover``/``close``. Cada linha da
    tabela que declara consumo em UMA das tensoes elegiveis (127 V/220 V)
    vira UMA linha achatada com ``tensao``, ``kwh_mes``, ``classe`` e
    ``source_id`` (``marca|modelo|tensao``). Colunas ``VA``, volumes e
    indices de eficiencia NAO sao ingeridos (unidade/significado
    incompativel com o contrato).

    Attributes:
        code: Constante ``"INMETRO"``.
    """

    def __init__(
        self,
        *,
        xlsx_bytes: bytes | None = None,
        xlsx_path: Path | None = None,
        url: str | None = None,
        timeout: float = 60.0,
        session: Any | None = None,
    ) -> None:
        if sum(value is not None for value in (xlsx_bytes, xlsx_path, url)) != 1:
            raise ValueError(
                "InmetroXlsxClient requer exatamente um entre xlsx_bytes, "
                "xlsx_path ou url"
            )
        self._bytes = xlsx_bytes
        self._path = xlsx_path
        self._url = url
        self._timeout = timeout
        self._session = session or requests

    @property
    def code(self) -> str:
        return SOURCE_CODE

    # ------------------------------------------------------------------ #
    # SourceClient protocol (DIP)
    # ------------------------------------------------------------------ #
    def fetch_page(
        self, dataset_id: str, *, limit: int, offset: int
    ) -> list[dict[str, Any]]:
        rows = self._fetch_rows()
        return rows[offset : offset + limit]

    def count(self, dataset_id: str) -> int:
        return len(self._fetch_rows())

    def discover(self) -> list[tuple[str, str]]:
        return [(DATASET_ID, "INMETRO PBE — Refrigeradores (XLSX oficial)")]

    def close(self) -> None:
        pass

    def __enter__(self) -> "InmetroXlsxClient":
        return self

    def __exit__(self, *_exc_info: object) -> None:
        self.close()

    # ------------------------------------------------------------------ #
    # Transporte real — UNICO ponto de contato com a fonte
    # ------------------------------------------------------------------ #
    def _fetch_rows(self) -> list[dict[str, Any]]:
        """Baixou/leu XLSX -> linhas achatadas ``{chave: valor}``."""
        payload = self._load_bytes()
        with zipfile.ZipFile(BytesIO(payload)) as zipped:
            rows = _sheet_rows(zipped)
        return self._flatten(rows)

    def _load_bytes(self) -> bytes:
        if self._bytes is not None:
            return self._bytes
        if self._path is not None:
            return self._path.read_bytes()
        assert self._url is not None
        response = self._session.get(self._url, timeout=self._timeout)
        response.raise_for_status()
        return response.content

    # ------------------------------------------------------------------ #
    # Parser estrutural (cabecalho multi-nivel -> linhas achatadas)
    # ------------------------------------------------------------------ #
    def _flatten(self, rows: list[dict[str, str]]) -> list[dict[str, Any]]:
        header_index = self._find_header_index(rows)
        if header_index is None:
            raise ValueError(
                "Cabecalho PBE nao encontrado (esperado FORNECEDOR/MARCA/"
                "MODELO na mesma linha) — formato da tabela mudou?"
            )

        labels = self._column_labels(rows, header_index)
        consumption = {
            letter: voltage
            for letter, (group, sub) in labels.items()
            if "consumo de energia" in group
            and (voltage := _INGESTIBLE_VOLTAGES.get(sub))
        }
        classes = {
            letter: (group, sub)
            for letter, (group, sub) in labels.items()
            if group.startswith("faixa de classificação")
            or group.startswith("faixa de classificacao")
        }

        marca_letter = self._single(labels, "marca")
        modelo_letter = self._single(labels, "modelo")
        registro_letter = self._letter_for(
            labels, "nº de registro"
        ) or self._letter_for(labels, "no de registro")
        tipo_letter = self._letter_for(labels, "tipo de produto")

        flat: list[dict[str, Any]] = []
        for row in rows[header_index + 3 :]:
            marca = (row.get(marca_letter) or "").strip()
            modelo = (row.get(modelo_letter) or "").strip()
            if not marca or not modelo:
                continue
            registro = (
                (row.get(registro_letter) or "").strip() if registro_letter else ""
            )
            tipo = (row.get(tipo_letter) or "").strip() if tipo_letter else ""

            for letter, voltage in sorted(consumption.items()):
                raw_value = (row.get(letter) or "").strip()
                try:
                    kwh_month = float(str(raw_value).replace(",", "."))
                except ValueError:
                    continue
                if kwh_month <= 0:
                    continue  # variante nao declarada nessa tensao

                flat.append(
                    {
                        "fornecedor": (
                            row.get(self._letter_for(labels, "fornecedor")) or ""
                        ).strip()
                        if self._letter_for(labels, "fornecedor")
                        else "",
                        "marca": marca,
                        "modelo": modelo,
                        "tipo_produto": tipo,
                        "categoria": tipo,
                        "sistema_degelo": (
                            row.get(self._letter_for(labels, "sistema de degelo")) or ""
                        ).strip()
                        if self._letter_for(labels, "sistema de degelo")
                        else "",
                        "agente_espuma": (
                            row.get(
                                self._letter_for(labels, "agente de expansão da espuma")
                            )
                            or ""
                        ).strip()
                        if self._letter_for(labels, "agente de expansão da espuma")
                        else "",
                        "no_de_registro": registro,
                        # Identidade inclui o N DE REGISTRO: a tabela real
                        # contem RE-REGISTROS do mesmo marca|modelo|tensao
                        # (verificado: BFG50B em 003271/2019 e 007591/2016
                        # com consumos distintos) — sem o registro, duas
                        # variantes legitimas colidiriam na chave
                        # UNIQUE(source, external_id).
                        "source_id": (
                            f"{marca}|{modelo}|{registro}|{voltage}"
                            if registro
                            else f"{marca}|{modelo}|{voltage}"
                        ),
                        "tensao": voltage,
                        "kwh_mes": str(kwh_month),
                        "classe": self._class_for(classes, row, voltage),
                    }
                )
        return flat

    @staticmethod
    def _find_header_index(rows: list[dict[str, str]]) -> int | None:
        for index, row in enumerate(rows):
            values = {_norm(value) for value in row.values()}
            if {"fornecedor", "marca", "modelo"} <= values:
                return index
        return None

    @staticmethod
    def _column_labels(
        rows: list[dict[str, str]], header_index: int
    ) -> dict[str, tuple[str, str]]:
        """Mapa letra -> (grupo, sub-grupo) dos 3 niveis de cabecalho.

        Cabecalhos mesclados (merged cells) guardam o texto SOMENTE na
        primeira celula do intervalo (verificado no XLSX real: a coluna
        ``220 V`` de consumo herda o grupo ``CONSUMO DE ENERGIA`` da
        celula mesclada M). Colunas de grupo vazio herdam o rotulo do
        grupo mais a ESQUERDA (forward-fill) — sem isso, variante 220 V
        seria silenciosamente ignorada.
        """
        group_row = rows[header_index]
        sub_row = rows[header_index + 2] if header_index + 2 < len(rows) else {}
        letters = sorted(set(group_row) | set(sub_row))
        labels: dict[str, tuple[str, str]] = {}
        carried = ""
        for letter in letters:
            group = _norm(group_row.get(letter))
            if group:
                carried = group
            else:
                group = carried
            sub = _norm(sub_row.get(letter))
            labels[letter] = (group, sub)
        return labels

    @staticmethod
    def _letter_for(labels: dict[str, tuple[str, str]], group: str) -> str | None:
        for letter, (group_label, _sub) in sorted(labels.items()):
            if group_label == _norm(group):
                return letter
        return None

    @classmethod
    def _single(cls, labels: dict[str, tuple[str, str]], group: str) -> str:
        letter = cls._letter_for(labels, group)
        if letter is None:
            raise ValueError(f"Coluna obrigatoria ausente na tabela PBE: {group!r}")
        return letter

    @staticmethod
    def _class_for(
        classes: dict[str, tuple[str, str]],
        row: dict[str, str],
        voltage: str,
    ) -> str | None:
        """Faixa de classificacao (ENCE) da tensao; Padrao 2022 antes de 2015."""
        chosen: list[tuple[int, str]] = []
        for letter, (group, sub) in classes.items():
            if sub != _norm(voltage):
                continue
            for preference_index, pattern in enumerate(_CLASS_PREFERENCE):
                if pattern in group:
                    value = (row.get(letter) or "").strip()
                    if value:
                        chosen.append((preference_index, value))
                    break
        if not chosen:
            return None
        chosen.sort()
        return chosen[0][1]


__all__ = [
    "DATASET_ID",
    "INMETRO_XLSX_URL",
    "SOURCE_CODE",
    "InmetroXlsxClient",
]
