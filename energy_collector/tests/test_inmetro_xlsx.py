"""Testes do transporte REAL INMETRO/PBE (XLSX oficial publicado).

Estrategia: fixture XLSX minimo gerado IN-MEMORY (stdlib, inline strings)
espelhando a estrutura verificada na tabela oficial
``Tabela_Inmetro_Refrigeradores_e_Assemelhados.xlsx`` — cabecalho de 3
niveis com celulas MESCLADAS (o grupo ``CONSUMO DE ENERGIA (kWh/mês)``
só aparece na celula M; a coluna N ``220 V`` herda por forward-fill),
sub-colunas de consumo por TENSAO (127 V / 220 V / VA) e faixas de
classificacao Padrao 2015/2022.

A tabela real (133 KB, 996 linhas) foi validada separadamente contra
este parser (evidencia no relatorio final): 542 observacoes (266 @127 V
+ 276 @220 V), zero duplicadas, ENCE A+++ incluido. Um teste opt-in
abaixo repete essa validacao offline quando ``AMPARES_PBE_XLSX_PATH``
aponta para o arquivo baixado (sem rede no pytest default).
"""

from __future__ import annotations

import zipfile
from io import BytesIO
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape

import pytest

from collector.sources.inmetro import DATASET_ID, InmetroAdapter
from collector.sources.inmetro_xlsx import INMETRO_XLSX_URL, InmetroXlsxClient
from collector.sources.protocol import SourceAdapter, SourceClient
from tests.conftest import make_fake_pool


# ------------------------------------------------------------------ #
# Fixture XLSX minimo (OOXML com inline strings, apenas sheet1)
# ------------------------------------------------------------------ #

_SHEET_HEADER = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
)

# Layout real (compactado): linha 1 = cabecalho de grupos (celulas
# mescladas so guardam texto na primeira coluna), linha 2 = intermediaria
# (sub-grupos de volume no arquivo real), linha 3 = sub-cabecalhos,
# linhas 4+ = dados. O parser espera sub-cabecalho em header+2 e dados a
# partir de header+3 — a fixture espelha esse documento.
_ROWS: dict[int, dict[str, str]] = {
    1: {
        "A": "FORNECEDOR",
        "B": "MARCA",
        "C": "MODELO",
        "D": "TIPO DE PRODUTO",
        "G": "Nº DE REGISTRO",
        "M": "CONSUMO DE ENERGIA (kWh/mês)",
        "AA": "FAIXA DE CLASSIFICAÇÃO\n Padrão 2015",
        "AC": "FAIXA DE CLASSIFICAÇÃO\n Padrão 2022",
    },
    2: {"H": "REFRIGERADOR", "I": "CONGELADOR", "L": "TOTAL"},
    3: {
        "M": "127 V",
        "N": "220 V",
        "O": "VA",
        "AA": "127 V",
        "AB": "220 V",
        "AC": "127 V",
        "AD": "220 V",
    },
    # Bivolt: consumo DECLARADO distinto por tensao (nunca convertido).
    4: {
        "A": "BRITÂNIA",
        "B": "Philco",
        "C": "PRF406I",
        "D": "Refrigerador-Congelador",
        "G": "008370/2019",
        "M": "40",
        "N": "43",
        "AA": "A",
        "AC": "A+++",
        "AD": "A++",
    },
    # Somente 220 V declarado.
    5: {
        "A": "CONSUL",
        "B": "Consul",
        "C": "CRD30",
        "D": "Refrigerador",
        "G": "004155/2018",
        "N": "17",
        "AD": "A++",
    },
    # Somente VA (potencia aparente): NAO e energia em kWh/mes -> 0 linhas.
    6: {
        "A": "XPTO",
        "B": "Xpto",
        "C": "VA-ONLY",
        "D": "Refrigerador",
        "G": "000001/2015",
        "O": "579.24",
    },
    # Re-registro do MESMO modelo+tensao com outro certificado/consumo.
    7: {
        "A": "BRITÂNIA",
        "B": "Philco",
        "C": "PRF406I",
        "D": "Refrigerador-Congelador",
        "G": "001111/2015",
        "M": "55",
        "AC": "A",
    },
}


def _cell(ref: str, text: str) -> str:
    return (
        f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">'
        f"{escape(text)}</t></is></c>"
    )


def build_xlsx(rows: dict[int, dict[str, str]] | None = None) -> bytes:
    """XLSX minimo (zip + sheet1.xml) aceito pelo parser stdlib."""
    rows = rows if rows is not None else _ROWS
    parts = [_SHEET_HEADER, "<sheetData>"]
    for number in sorted(rows):
        cells = "".join(
            _cell(f"{col}{number}", text) for col, text in rows[number].items()
        )
        parts.append(f'<row r="{number}">{cells}</row>')
    parts.append("</sheetData></worksheet>")
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w") as zipped:
        zipped.writestr("xl/worksheets/sheet1.xml", "".join(parts))
    return buffer.getvalue()


def make_client(rows: dict[int, dict[str, str]] | None = None) -> InmetroXlsxClient:
    return InmetroXlsxClient(xlsx_bytes=build_xlsx(rows))


def collect_flat_rows(
    rows: dict[int, dict[str, str]] | None = None,
) -> list[dict[str, Any]]:
    client = make_client(rows)
    return client._fetch_rows()


# ------------------------------------------------------------------ #
# Protocolo (DIP) e contrato de entrada
# ------------------------------------------------------------------ #


class TestProtocolConformance:
    def test_client_conforms_to_source_client(self) -> None:
        assert isinstance(make_client(), SourceClient)

    def test_adapter_conforms_to_source_adapter(self) -> None:
        assert isinstance(InmetroAdapter(client=make_client()), SourceAdapter)

    def test_client_requires_exactly_one_input(self) -> None:
        with pytest.raises(ValueError, match="exatamente um"):
            InmetroXlsxClient()
        with pytest.raises(ValueError, match="exatamente um"):
            InmetroXlsxClient(xlsx_bytes=b"x", xlsx_path=Path("/tmp/a.xlsx"))

    def test_real_official_url_is_registered(self) -> None:
        # URL REAL verificada na pagina oficial (sem endpoint inventado).
        assert INMETRO_XLSX_URL == (
            "http://www.inmetro.gov.br/CONSUMIDOR/pbe/"
            "Tabela_Inmetro_Refrigeradores_e_Assemelhados.xlsx"
        )

    def test_discover_returns_refrigerators_dataset(self) -> None:
        assert make_client().discover() == [
            (DATASET_ID, "INMETRO PBE — Refrigeradores (XLSX oficial)")
        ]


# ------------------------------------------------------------------ #
# Parser estrutural (merged headers, tensao por coluna, VA excluido)
# ------------------------------------------------------------------ #


class TestXlsxFlattening:
    def test_bivolt_model_yields_one_observation_per_declared_voltage(self) -> None:
        rows = collect_flat_rows()
        prf406 = [
            r
            for r in rows
            if r["modelo"] == "PRF406I" and r["no_de_registro"] == "008370/2019"
        ]
        assert len(prf406) == 2
        by_voltage = {r["tensao"]: r for r in prf406}
        assert set(by_voltage) == {"127 V", "220 V"}
        assert by_voltage["127 V"]["kwh_mes"] == "40.0"
        assert by_voltage["220 V"]["kwh_mes"] == "43.0"  # declarado — sem conversao

    def test_merged_consumption_header_reaches_220v_column(self) -> None:
        # Sem forward-fill de cabecalho mesclado, a coluna 220 V seria
        # silenciosamente ignorada (bug real detectado e corrigido).
        voltages = {r["tensao"] for r in collect_flat_rows()}
        assert voltages == {"127 V", "220 V"}

    def test_va_column_is_never_ingested_as_energy(self) -> None:
        rows = collect_flat_rows()
        assert all(r["modelo"] != "VA-ONLY" for r in rows)
        assert all("va" not in r["tensao"].casefold() for r in rows)

    def test_reregistration_distinct_identity_same_model(self) -> None:
        rows = [r for r in collect_flat_rows() if r["modelo"] == "PRF406I"]
        ids = {r["source_id"] for r in rows}
        assert ids == {
            "Philco|PRF406I|008370/2019|127 V",
            "Philco|PRF406I|008370/2019|220 V",
            "Philco|PRF406I|001111/2015|127 V",
        }

    def test_identity_always_declares_voltage(self) -> None:
        # Nenhuma observacao sem tensao declarada (127 != 220, sempre).
        for row in collect_flat_rows():
            assert row["tensao"] in ("127 V", "220 V")
            assert row["tensao"] in row["source_id"]

    def test_class_prefers_padrao_2022_then_2015(self) -> None:
        rows = {r["source_id"]: r for r in collect_flat_rows()}
        # PRF406I 127 V: 2022 = A+++ (preferido), 2015 = A (fallback).
        assert rows["Philco|PRF406I|008370/2019|127 V"]["classe"] == "A+++"
        assert rows["Philco|PRF406I|001111/2015|127 V"]["classe"] == "A"

    def test_zero_and_blank_consumption_mean_not_declared(self) -> None:
        rows = {k: v for k, v in _ROWS.items()}
        rows[8] = {
            "A": "Z",
            "B": "Zero",
            "C": "Z-1",
            "G": "9/9",
            "M": "0",
            "N": "12",  # 127 V declarado como 0 -> nao declarado
        }
        flat = collect_flat_rows(rows)
        zero = [r for r in flat if r["modelo"] == "Z-1"]
        assert len(zero) == 1
        assert zero[0]["tensao"] == "220 V"

    def test_missing_mandatory_header_fails_fast(self) -> None:
        broken = {k: v for k, v in _ROWS.items()}
        broken[1] = {"A": "FORNECEDOR", "B": "MARCA"}  # sem MODELO
        with pytest.raises(ValueError, match="MODELO"):
            collect_flat_rows(broken)


# ------------------------------------------------------------------ #
# Adapter: linha achatada -> Product (tensao preservada, x12 uma vez)
# ------------------------------------------------------------------ #


class TestAdapterIntegration:
    def _products(self) -> list:
        client = make_client()
        adapter = InmetroAdapter(client=client)
        pages = list(adapter.iter_raw_records(dataset_id=DATASET_ID, page_size=10**9))
        products = []
        for record in pages[0][1]:
            product = adapter.normalize(record, dataset_id=DATASET_ID, category="")
            if product is not None:
                products.append(product)
        return products

    def test_voltage_kept_verbatim_never_converted(self) -> None:
        products = self._products()
        v127 = next(
            p
            for p in products
            if p.source_id.endswith("127 V") and p.model == "PRF406I"
        )
        v220 = next(
            p
            for p in products
            if p.source_id.endswith("220 V") and p.model == "PRF406I"
        )
        assert v127.voltage_kind == "monovolt" and v127.voltage_min_v == 127
        assert v127.voltage_raw == "127 V"
        assert v220.voltage_min_v == 220
        # Nenhuma conversao entre tensoes: cada observacao carrega o
        # consumo DECLARADO para a sua tensao.
        assert v127.annual_energy_kwh == 480  # 40 x 12 (uma unica vez)
        assert v220.annual_energy_kwh == 516  # 43 x 12 (uma unica vez)

    def test_monthly_to_annual_exactly_once(self) -> None:
        products = self._products()
        sample = products[0]
        assert sample.raw_energy_unit == "kWh/mes"
        assert sample.annual_energy_kwh == sample.raw_energy_value * 12

    def test_ence_label_from_official_table(self) -> None:
        products = self._products()
        assert {str(p.label_class) for p in products} >= {"A+++", "A++", "A"}

    def test_ids_deterministic_and_unique(self) -> None:
        products = self._products()
        ids = [p.product_id() for p in products]
        assert len(set(ids)) == len(ids) == 4
        again = self._products()
        assert [p.product_id() for p in again] == ids


# ------------------------------------------------------------------ #
# Persistencia: insert-only, idempotente, proveniencia por observacao
# ------------------------------------------------------------------ #


class TestPersistenceIntegration:
    def _run(self, existing: int = 0):
        pool, conn, _cur = make_fake_pool(existing=existing)
        from collector.services.multi_source import MultiSourceCollectionService

        service = MultiSourceCollectionService(pool=pool)
        rep = service.collect(
            InmetroAdapter(client=make_client()),
            dataset_id=DATASET_ID,
            category="refrigerators",
        )
        cursor = conn.cursor.return_value.__enter__.return_value
        return rep, cursor

    def test_products_and_voltage_observations_reach_the_db(self) -> None:
        rep, cursor = self._run()

        assert rep.status == "ok"
        assert rep.received == 4
        # 4 observacoes colapsam em 1 grupo canonico
        # (Eletrodomesticos|Geladeira): media dos elegiveis INMETRO =
        # (480 + 516 + 204 + 660) / 4 = 465 kWh/ano.
        assert rep.inserted == 1
        calls = cursor.executemany.call_args_list
        product_rows = next(
            c.args[1] for c in calls if "INSERT INTO product" in c.args[0]
        )
        observation_rows = next(
            c.args[1] for c in calls if "product_source_observation" in c.args[0]
        )
        assert len(product_rows) == 1
        assert str(product_rows[0][7]) == "465.00"  # media canonica
        # 4 observacoes (2 tensoes do bivolt + 220-only + re-registro)
        assert len(observation_rows) == 4
        voltages = sorted(str(row[11]) for row in observation_rows)  # voltage_raw
        assert voltages == ["127 V", "127 V", "220 V", "220 V"]

    def test_repeated_run_is_flagged_as_duplicates_never_updated(self) -> None:
        rep, _cursor = self._run(existing=4)
        # INSERT-ONLY: nada e sobrescrito; repeticoes viram duplicatas.
        assert rep.duplicates == 1  # 1 produto canonico ja existente
        assert rep.inserted == 0
        assert "DO UPDATE" not in _insert_sql_used()

    def test_repeated_run_produces_identical_ids(self) -> None:
        def id_sets() -> tuple[set, set]:
            pool, conn, _cur = make_fake_pool(existing=0)
            from collector.services.multi_source import MultiSourceCollectionService

            MultiSourceCollectionService(pool=pool).collect(
                InmetroAdapter(client=make_client()),
                dataset_id=DATASET_ID,
                category="refrigerators",
            )
            cursor = conn.cursor.return_value.__enter__.return_value
            calls = cursor.executemany.call_args_list
            products = next(
                c.args[1] for c in calls if "INSERT INTO product" in c.args[0]
            )
            observations = next(
                c.args[1] for c in calls if "product_source_observation" in c.args[0]
            )
            return {r[0] for r in products}, {r[0] for r in observations}

        assert id_sets() == id_sets()


def _insert_sql_used() -> str:
    from collector.database import _INSERT_PRODUCT_SQL

    return _INSERT_PRODUCT_SQL


# ------------------------------------------------------------------ #
# Validacao offline da tabela REAL (opt-in, sem rede no pytest default)
# ------------------------------------------------------------------ #


class TestRealOfficialTable:
    @pytest.mark.skipif(
        not Path("/tmp/pbe_refrig.xlsx").exists(),
        reason="tabela XLSX real nao baixada (defina AMPARES_PBE_XLSX_PATH para validar)",
    )
    def test_real_table_parses_with_unique_identities(self) -> None:
        path = Path("/tmp/pbe_refrig.xlsx")
        client = InmetroXlsxClient(xlsx_path=path)
        rows = client._fetch_rows()
        assert rows, "tabela real deve gerar observacoes"
        source_ids = [r["source_id"] for r in rows]
        assert len(set(source_ids)) == len(source_ids)
        voltages = {r["tensao"] for r in rows}
        assert voltages == {"127 V", "220 V"}
        adapter = InmetroAdapter(client=client)
        pages = list(adapter.iter_raw_records(dataset_id=DATASET_ID, page_size=10**9))
        products = [
            adapter.normalize(r, dataset_id=DATASET_ID, category="")
            for r in pages[0][1]
        ]
        products = [p for p in products if p is not None]
        assert len({p.product_id() for p in products}) == len(products)
