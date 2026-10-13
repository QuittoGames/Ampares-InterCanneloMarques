"""Regressoes da spec "Brazil-Aware Product Normalization" (secao 8).

Cobre os cenarios exigidos pela spec que nao sao repetidos nos testes
especificos de cada modulo:

* Declaracao de tensao verificada (110 V x 127 V x bivolt x faixa x
  desconhecida) — preservada, NUNCA convertida.
* Modelo estrangeiro 220 V sem equivalente brasileiro — nunca fabrica
  equivalencia brasileira.
* anual x mensal nunca confundidos; mensal -> anual exatamente UMA vez.
* Fonte estrangeira/generica nunca sobrescreve especificacao brasileira
  verificada; registros incomparaveis nunca sao media-los.
* Colecao repetida idempotente (sem produtos/observacoes duplicados).
* Contrato canonico = Product.java = create.sql = diagrama (sinergia).
* Falha em fonte viva nao apaga dados validos pre-existentes.
* Migracao 005 idempotente e nao-destrutiva.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from decimal import Decimal
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import pytest

from collector.database import _INSERT_PRODUCT_SQL
from collector.models import Product, merge_products, source_observation
from collector.precedence import (
    CANONICAL_SOURCE,
    is_canonical_eligible,
    source_tier,
)
from collector.services.multi_source import MultiSourceCollectionService
from collector.sources.inmetro import DATASET_ID, InmetroAdapter, InmetroClient
from collector.voltage import (
    KIND_BIVOLT,
    KIND_MONOVOLT,
    KIND_RANGE,
    KIND_UNKNOWN,
    parse_voltage,
)
from tests.conftest import make_fake_pool, make_product

_REPO_ROOT = Path(__file__).resolve().parents[2]
_JAVA_PRODUCT = (
    _REPO_ROOT / "src/main/java/cannelo/marques/interdisciplinar/interdisciplinar/"
    "Models/Product.java"
)
_CREATE_SQL_PATH = _REPO_ROOT / "migrations/create.sql"
_MIGRATION_005 = _REPO_ROOT / "migrations/005_canonical_product_contract.sql"
_MIGRATION_006 = _REPO_ROOT / "migrations/006_collector_ingestion_tables.sql"
_DRAWIO = _REPO_ROOT / "docs/arquiteture.drawio"

CSV_MONTHLY = (
    "marca,modelo,categoria,classe,kwh_mes,tensao\nElectrolux,DC50,1,A,30,127 V\n"
)
CSV_ANNUAL = (
    "marca,modelo,categoria,classe,kwh_year,tensao\n"
    "Consul,CRD30,5,B,500,Bivolt 110/220\n"
)
CSV_NO_VOLTAGE = "marca,modelo,categoria,classe,kwh_mes\nElectrolux,DC50,1,A,30\n"
CSV_NO_ENERGY = "marca,modelo,categoria,tensao\nElectrolux,DC50,1,127 V\n"


def _inmetro_product(csv_content: str, index: int = 0) -> Product:
    adapter = InmetroAdapter(client=InmetroClient(csv_content=csv_content))
    pages = list(adapter.iter_raw_records(dataset_id=DATASET_ID, page_size=10))
    records = pages[0][1]
    product = adapter.normalize(records[index], dataset_id=DATASET_ID, category="")
    assert product is not None
    return product


# ------------------------------------------------------------------ #
# 1. Tensao declarada — preservada, distinta e nunca convertida
# ------------------------------------------------------------------ #


class TestVoltageDeclarations:
    def test_explicit_110_label_stays_110(self) -> None:
        spec = parse_voltage("110 V")
        assert spec.kind == KIND_MONOVOLT
        assert spec.min_v == Decimal("110")
        assert spec.max_v == Decimal("110")
        assert spec.raw == "110 V"

    def test_explicit_127_spec_stays_127_and_differs_from_110(self) -> None:
        spec = parse_voltage("127 V")
        assert spec.kind == KIND_MONOVOLT
        assert spec.min_v == Decimal("127")
        # Um rotulo 110 V e uma especificacao 127 V sao coisas DIFERENTES.
        assert parse_voltage("110 V").min_v != spec.min_v

    def test_220_is_preserved_never_rewritten_to_110_or_127(self) -> None:
        spec = parse_voltage("220 V")
        assert spec.kind == KIND_MONOVOLT
        assert spec.min_v == Decimal("220")

    def test_bivolt_declaration(self) -> None:
        spec = parse_voltage("Bivolt 110/220")
        assert spec.kind == KIND_BIVOLT
        assert spec.min_v == Decimal("110")
        assert spec.max_v == Decimal("220")

    def test_voltage_range_declaration(self) -> None:
        spec = parse_voltage("100-240 V")
        assert spec.kind == KIND_RANGE
        assert spec.min_v == Decimal("100")
        assert spec.max_v == Decimal("240")

    @pytest.mark.parametrize("value", [None, "", "  ", "n/a", "NÃO INFORMADO"])
    def test_missing_voltage_is_marked_unknown(self, value: Any) -> None:
        spec = parse_voltage(value)
        assert spec.kind == KIND_UNKNOWN
        assert spec.min_v is None and spec.max_v is None


# ------------------------------------------------------------------ #
# 2. Modelo brasileiro verificado com tensao declarada (PBE)
# ------------------------------------------------------------------ #


class TestVerifiedBrazilianModel:
    def test_brazilian_model_carries_voltage_and_label(self) -> None:
        product = _inmetro_product(CSV_MONTHLY)
        assert product.source == "INMETRO"
        assert product.is_generic is False
        assert product.voltage_kind == KIND_MONOVOLT
        assert product.voltage_min_v == Decimal("127")
        assert product.voltage_raw == "127 V"
        assert product.label_class == "A"

    def test_brazilian_model_monthly_energy_converted_exactly_once(self) -> None:
        product = _inmetro_product(CSV_MONTHLY)
        # 30 kWh/mes x 12 = 360 kWh/ano — e NADA de 30x12x12.
        assert product.annual_energy_kwh == Decimal("360.00")
        assert product.raw_energy_value == Decimal("30")
        assert product.raw_energy_unit == "kWh/mes"

    def test_annual_declaration_is_never_monthly_multipled_again(self) -> None:
        product = _inmetro_product(CSV_ANNUAL)
        # kwh_year=500 ANUAL vira 500 — nao 6000 nem 1000.
        assert product.annual_energy_kwh == Decimal("500")
        assert product.raw_energy_value == Decimal("500")
        assert product.raw_energy_unit == "kWh/ano"
        # e a tensao bivolt declarada vem junto
        assert product.voltage_kind == KIND_BIVOLT
        assert product.voltage_min_v == Decimal("110")
        assert product.voltage_max_v == Decimal("220")

    def test_missing_voltage_stays_unknown_not_inferred(self) -> None:
        product = _inmetro_product(CSV_NO_VOLTAGE)
        assert product.voltage_kind == KIND_UNKNOWN
        assert product.voltage_min_v is None
        assert product.voltage_raw is None

    def test_record_without_energy_is_discarded_not_invented(self) -> None:
        adapter = InmetroAdapter(client=InmetroClient(csv_content=CSV_NO_ENERGY))
        pages = list(adapter.iter_raw_records(dataset_id=DATASET_ID, page_size=10))
        assert (
            adapter.normalize(pages[0][1][0], dataset_id=DATASET_ID, category="")
            is None
        )


# ------------------------------------------------------------------ #
# 3. Modelo estrangeiro 220 V sem equivalente brasileiro
# ------------------------------------------------------------------ #


class TestForeignModelWithoutBrazilianEquivalent:
    def test_foreign_220v_record_never_becomes_canonical_metrics(self) -> None:
        foreign = make_product(
            source="ENERGY STAR",
            source_id="us-1",
            brand="SameBrand",
            model="US-220",
            power=Decimal("100"),
            annual=Decimal("500"),
        )
        foreign_voltage = parse_voltage("220 V")

        merged = merge_products([foreign])

        # Registro canonico existe apenas como ancora das observacoes:
        # sem marca/modelo validados e SEM metricas inventadas.
        assert len(merged) == 1
        assert merged[0].source == CANONICAL_SOURCE
        assert merged[0].brand is None
        assert merged[0].model is None
        assert merged[0].avg_power_w is None
        assert merged[0].annual_energy_kwh is None
        # A referencia estrangeira continua disponivel NA observacao,
        # com a tensao original preservada (nunca "brazilizada").
        observation = source_observation(foreign)
        assert observation.source == "ENERGY STAR"
        assert foreign_voltage.min_v == Decimal("220")

    def test_same_brand_model_across_sources_stays_two_records(self) -> None:
        # Mesmo brand/model em fonte estrangeira e brasileira => UUIDs
        # distintos: nunca sao o mesmo modelo por semelhanca de rotulo.
        foreign = make_product(
            source="ENERGY STAR", source_id="x", brand="Electrolux", model="DC50"
        )
        brazilian = make_product(
            source="INMETRO",
            source_id="Electrolux|DC50",
            brand="Electrolux",
            model="DC50",
        )
        assert foreign.product_id() != brazilian.product_id()


# ------------------------------------------------------------------ #
# 4. Precedencia de fontes e projecao canonica
# ------------------------------------------------------------------ #


class TestSourcePrecedence:
    @pytest.mark.parametrize(
        ("source", "tier"),
        [
            ("INMETRO", "primary"),
            ("ENERGY STAR", "foreign"),
            ("ENERGY_STAR", "foreign"),
            ("WATTSIMPLE", "generic"),
            ("IEA", "aggregate"),
            ("FONTE_NOVA", "unknown"),
        ],
    )
    def test_source_tiers(self, source: str, tier: str) -> None:
        assert source_tier(source) == tier

    def test_only_primary_brazilian_non_generic_records_are_eligible(self) -> None:
        assert is_canonical_eligible(make_product(source="INMETRO")) is True
        assert is_canonical_eligible(make_product(source="ENERGY STAR")) is False
        assert is_canonical_eligible(make_product(source="WATTSIMPLE")) is False
        assert (
            is_canonical_eligible(make_product(source="INMETRO", is_generic=True))
            is False
        )

    def test_generic_and_foreign_never_averaged_with_brazilian(self) -> None:
        # Registros incomparaveis (generico x estrangeiro x brasileiro)
        # nao compartilham populacao: so o BR brasileiro conta.
        products = [
            make_product(source="WATTSIMPLE", source_id="g", annual=Decimal("1")),
            make_product(source="ENERGY STAR", source_id="f", annual=Decimal("2")),
            make_product(source="INMETRO", source_id="b", annual=Decimal("360")),
        ]
        merged = merge_products(products)
        assert merged[0].annual_energy_kwh == Decimal("360")

    def test_foreign_run_after_brazilian_run_yields_unavailable_metrics(
        self,
    ) -> None:
        # Rodada 1 (INMETRO) fornece 360 kWh/ano; rodada 2 (ENERGY STAR)
        # nao tem valor elegivel -> projecao fica indisponivel e, pela
        # politica INSERT-ONLY (spec secao 6), a execucao estrangeira
        # NAO TOCA na linha existente (DO NOTHING protege o dado
        # brasileiro verificado sem nunca atualiza-lo).
        run1 = merge_products(
            [make_product(source="INMETRO", source_id="b", annual=Decimal("360"))]
        )
        run2 = merge_products(
            [make_product(source="ENERGY STAR", source_id="f", annual=Decimal("500"))]
        )
        assert run1[0].annual_energy_kwh == Decimal("360")
        assert run2[0].annual_energy_kwh is None
        assert "ON CONFLICT (id) DO NOTHING" in _INSERT_PRODUCT_SQL
        assert "DO UPDATE" not in _INSERT_PRODUCT_SQL


# ------------------------------------------------------------------ #
# 5. Observacao de origem: proveniencia + idempotencia
# ------------------------------------------------------------------ #


class TestObservationProvenanceAndIdempotency:
    def test_observation_carries_voltage_and_generic_flag(self) -> None:
        generic = make_product(source="WATTSIMPLE", source_id="g1", is_generic=True)
        observation = source_observation(generic)
        assert observation.is_generic is True
        assert observation.voltage_kind == KIND_UNKNOWN  # fonte sem tensao

    def test_repeated_collection_generates_identical_ids(self) -> None:
        adapter = InmetroAdapter(client=InmetroClient(csv_content=CSV_MONTHLY))

        def run() -> tuple[set[Any], set[Any]]:
            pool, conn, _cur = make_fake_pool(existing=0)
            service = MultiSourceCollectionService(pool=pool)
            service.collect(adapter, dataset_id=DATASET_ID, category="refrig")
            cursor = conn.cursor.return_value.__enter__.return_value
            calls = cursor.executemany.call_args_list
            product_ids = {
                row[0]
                for call in calls
                if "INSERT INTO product\n" in (call.args[0] or "")
                for row in call.args[1]
            }
            observation_ids = {
                row[0]
                for call in calls
                if "product_source_observation" in (call.args[0] or "")
                for row in call.args[1]
            }
            return product_ids, observation_ids

        first_products, first_observations = run()
        second_products, second_observations = run()

        assert len(first_products) == 1  # Electrolux DC50
        assert first_products == second_products
        assert first_observations == second_observations
        assert not (first_products & first_observations)  # tabelas distintas

    def test_missing_power_stays_unavailable_through_observation(self) -> None:
        product = _inmetro_product(CSV_MONTHLY)
        observation = source_observation(product)
        assert observation.power_w is None  # PBE nao declara potencia
        assert observation.annual_energy_kwh == Decimal("360.00")
        assert observation.raw_energy_unit == "kWh/mes"


# ------------------------------------------------------------------ #
# 6. Sinergia de contrato: Java <-> create.sql <-> DDL coletor <-> drawio
# ------------------------------------------------------------------ #


def _java_fields() -> set[str]:
    source = _JAVA_PRODUCT.read_text(encoding="utf-8")

    def _snake(name: str) -> str:
        return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()

    return {
        _snake(field)
        for field in re.findall(
            r"^\s*private\s+[\w.<>\[\]]+\s+(\w+);", source, re.MULTILINE
        )
    }


def _sql_columns(sql: str, table: str) -> set[str]:
    match = re.search(
        rf"CREATE TABLE IF NOT EXISTS {table}\s*\((.*?)\n\)", sql, re.DOTALL
    )
    assert match, f"tabela {table} nao encontrada"
    return set(
        re.findall(
            r"^\s{4}(\w+)\s+(?:UUID|VARCHAR\(\d+\)|NUMERIC|BOOLEAN|TIMESTAMPTZ|SERIAL)",
            match.group(1),
            re.MULTILINE,
        )
    )


def _drawio_table_fields(table_value: str) -> set[str]:
    tree = ET.parse(_DRAWIO)
    container_id = None
    for cell in tree.iter("mxCell"):
        if cell.get("value") == table_value:
            container_id = cell.get("id")
            break
    assert container_id, f"tabela {table_value} nao encontrada no diagrama"
    row_ids = {
        cell.get("id")
        for cell in tree.iter("mxCell")
        if cell.get("parent") == container_id
    }
    fields: set[str] = set()
    for cell in tree.iter("mxCell"):
        if cell.get("parent") in row_ids and cell.get("value"):
            value = cell.get("value") or ""
            if ": " in value:
                fields.add(value.split(": ", 1)[0])
    return fields


class TestCanonicalContractAgreement:
    def test_all_sources_agree_on_product_fields(self) -> None:
        java_fields = _java_fields()
        create_sql_fields = _sql_columns(
            _CREATE_SQL_PATH.read_text(encoding="utf-8"), "product"
        )
        drawio_fields = _drawio_table_fields("Product")

        assert java_fields == create_sql_fields == drawio_fields
        # Exatamente o contrato de 8 campos da spec (secao 1).
        assert len(java_fields) == 8
        # Nada de tensao/standby/is_generic no produto canonico.
        assert "voltage" not in java_fields
        assert "standby_power_w" not in java_fields
        assert "is_generic" not in java_fields
        assert "avg_idle_energy_for_hour" not in drawio_fields
        assert "subcategory" in drawio_fields

    def test_observation_table_agrees_with_diagram(self) -> None:
        ddl_fields = _sql_columns(
            _CREATE_SQL_PATH.read_text(encoding="utf-8"),
            "product_source_observation",
        )
        drawio_fields = _drawio_table_fields("product_source_observation")
        assert ddl_fields == drawio_fields
        # O campo de energia ociosa do diagrama virou standby_power_w
        # com unidade explicita AQUI (observacao), nao no produto.
        assert "standby_power_w" in ddl_fields
        assert "is_generic" in ddl_fields
        assert "voltage_kind" in ddl_fields

    @staticmethod
    def _assert_non_destructive(sql: str) -> None:
        active = "\n".join(
            line for line in sql.splitlines() if not line.strip().startswith("--")
        )
        for destructive in ("DROP TABLE", "DELETE FROM", "TRUNCATE", "DROP COLUMN"):
            assert destructive not in active

    def test_migrations_are_idempotent_and_non_destructive(self) -> None:
        # 005: subcategory + proveniencia da observacao; 006: tabelas de
        # ingestao (ENCE/agregados) que sairam do DDL runtime do coletor.
        assert "subcategory" in _MIGRATION_005.read_text(encoding="utf-8")
        assert "voltage_kind" in _MIGRATION_005.read_text(encoding="utf-8")
        sql6 = _MIGRATION_006.read_text(encoding="utf-8")
        assert "energy_label_class" in sql6
        assert "aggregate_reference" in sql6
        for path in (_MIGRATION_005, _MIGRATION_006):
            sql = path.read_text(encoding="utf-8")
            assert "IF NOT EXISTS" in sql
            self._assert_non_destructive(sql)


# ------------------------------------------------------------------ #
# 7. Falha em fonte viva nao apaga dados validos
# ------------------------------------------------------------------ #


class _FailingAdapter:
    code = "ENERGY_STAR"
    source_type = "individual_product"

    def iter_raw_records(self, **_kwargs: Any) -> Any:
        raise RuntimeError("rede indisponivel (simulado)")
        yield  # pragma: no cover

    def normalize(self, *_a: Any, **_k: Any) -> Any:  # pragma: no cover
        return None


class _PartialFailingAdapter:
    """Produz uma pagina valida e depois falha (fonte cai no meio)."""

    code = "INMETRO"
    source_type = "individual_product"

    def __init__(self) -> None:
        self._adapter = InmetroAdapter(client=InmetroClient(csv_content=CSV_MONTHLY))

    def iter_raw_records(self, **kwargs: Any) -> Any:
        first = True
        for item in self._adapter.iter_raw_records(**kwargs):
            if first:
                first = False
                yield item
            else:  # pragma: no cover
                break
        raise RuntimeError("fonte caiu no meio da varredura")

    def normalize(self, *a: Any, **k: Any) -> Any:
        return self._adapter.normalize(*a, **k)


class TestLiveFailureDoesNotEraseData:
    def test_total_failure_performs_no_writes_at_all(self) -> None:
        pool, conn, _cur = make_fake_pool(existing=7)
        service = MultiSourceCollectionService(pool=pool)

        rep = service.collect(_FailingAdapter(), dataset_id="d", category="c")

        assert rep.status == "failed"
        cursor = conn.cursor.return_value.__enter__.return_value
        assert cursor.executemany.call_count == 0

    def test_mid_run_failure_never_writes_products(self) -> None:
        pool, conn, _cur = make_fake_pool(existing=7)
        service = MultiSourceCollectionService(pool=pool)

        rep = service.collect(
            _PartialFailingAdapter(), dataset_id=DATASET_ID, category="refrig"
        )

        assert rep.status == "failed"
        assert rep.received == 1  # dados chegaram...
        cursor = conn.cursor.return_value.__enter__.return_value
        calls = cursor.executemany.call_args_list
        # ...mas nada foi persistido: sem INSERT de produto, sem DELETE.
        for call in calls:
            sql = call.args[0] or ""
            assert "INSERT INTO product" not in sql
            assert "DELETE" not in sql.upper()
