"""Testes de integracao fina do CLI multi-fonte (PR 6).

Sem rede/banco: valida o PARSER (flags, defaults, rejeicao de fonte
invalida) e o REGISTRO (montagem das specs). O caminho legado sem
``--source`` e bit-identicamente o historico — coberto pelos testes do
``CollectionService`` e ``data_collector`` existentes.
"""

from __future__ import annotations

import pytest

import data_collector
from collector.sources.registry import SOURCES, available_sources


class TestParser:
    def test_default_source_is_none_legacy_path(self) -> None:
        args = data_collector.build_parser().parse_args(["--all"])
        assert args.source is None

    def test_source_accepts_registered(self) -> None:
        args = data_collector.build_parser().parse_args(
            ["--source", "energy-star", "--all"]
        )
        assert args.source == "energy-star"

    def test_source_rejects_unknown(self) -> None:
        with pytest.raises(SystemExit) as exc:
            data_collector.build_parser().parse_args(
                ["--source", "unknown-source", "--all"]
            )
        assert exc.value.code == 2

    def test_source_with_category(self) -> None:
        args = data_collector.build_parser().parse_args(
            ["--source", "energy-star", "--category", "televisions"]
        )
        assert args.category == "televisions"


class TestRegistry:
    def test_energy_star_spec_makes_adapter_and_client(self) -> None:
        spec = SOURCES["energy-star"](None, 4.0)
        assert spec["code"] == "ENERGY_STAR"
        client = spec["make_client"]()
        adapter = spec["make_adapter"]()
        from collector.sources.energy_star import EnergyStarAdapter, EnergyStarClient
        from collector.sources.protocol import SourceAdapter, SourceClient

        assert isinstance(client, EnergyStarClient)
        assert isinstance(adapter, EnergyStarAdapter)
        assert isinstance(client, SourceClient)
        assert isinstance(adapter, SourceAdapter)

    def test_available_sources_sorted(self) -> None:
        assert available_sources() == sorted(available_sources())

    def test_wattsimple_is_registered(self) -> None:
        assert "wattsimple" in available_sources()


class TestLegacyPathUntouched:
    def test_make_client_signature_unchanged(self) -> None:
        """O main() legado usa make_client() -> SocrataClient; o multi-
        source tem helper proprio (_run_multi_source) — nenhum overlap."""
        import inspect

        src = inspect.getsource(data_collector.main)
        assert "if args.source:" in src
        assert "service = CollectionService(" in src  # caminho legado vivo
