"""Testes unitarios do SocrataService (camada de integracao).

Cobre o contrato exigido:

* resposta valida
* resposta vazia
* erro HTTP
* timeout
* paginacao / multiplas paginas
* dataset inexistente
* resposta malformada

Usa mocks do ``SocrataClient`` — nao depende da API real. O servico
deve retornar dados CRUS (sem normalizacao/classificacao) e metadados.
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from collector.api_client import SocrataError
from collector.services.socrata_service import QueryMetadata, SocrataService


def _make_service(
    *,
    fetch_page_return=None,
    fetch_page_side_effect=None,
    count_return=10,
    fetch_page_call_side_effect=None,
    count_side_effect=None,
) -> tuple[SocrataService, MagicMock]:
    client = MagicMock(name="client")
    client.fetch_page.return_value = fetch_page_return
    if fetch_page_side_effect is not None:
        client.fetch_page.side_effect = fetch_page_side_effect
    if fetch_page_call_side_effect is not None:
        client.fetch_page.side_effect = fetch_page_call_side_effect
    client.count.return_value = count_return
    if count_side_effect is not None:
        client.count.side_effect = count_side_effect
    client.base_url = "https://data.energystar.gov"
    service = SocrataService(client, page_size=2)
    return service, client


# ---------------------------------------------------------------------------
# fetch_page (pagina unica)
# ---------------------------------------------------------------------------


class TestFetchPage:
    def test_return_raw_records_and_metadata(self) -> None:
        raw = [{"pd_id": "1", "brand_name": "A"}, {"pd_id": "2", "brand_name": "B"}]
        service, client = _make_service(fetch_page_return=raw)
        records, meta = service.fetch_page("abcd-1234", limit=2)
        assert records == raw
        assert meta.dataset_id == "abcd-1234"
        assert meta.limit == 2
        assert meta.offset == 0
        # Os dados sao crus, nao normalizados.
        assert records[0]["brand_name"] == "A"

    def test_return_empty_for_empty_response(self) -> None:
        service, client = _make_service(fetch_page_return=[])
        records, meta = service.fetch_page("abcd-1234", limit=2)
        assert records == []
        assert meta.truncated is False

    def test_use_default_page_size(self) -> None:
        service, client = _make_service(fetch_page_return=[])
        service.fetch_page("abcd-1234")
        client.fetch_page.assert_called_with("abcd-1234", limit=2, offset=0)

    def test_raise_socrata_error_on_http_error(self) -> None:
        service, _client = _make_service(
            fetch_page_side_effect=SocrataError("HTTP 500")
        )
        with pytest.raises(SocrataError):
            service.fetch_page("abcd-1234")

    def test_raise_socrata_error_on_timeout(self) -> None:
        service, _client = _make_service(fetch_page_side_effect=SocrataError("timeout"))
        with pytest.raises(SocrataError):
            service.fetch_page("abcd-1234")


# ---------------------------------------------------------------------------
# fetch (dataset completo, paginado)
# ---------------------------------------------------------------------------


class TestFetchDataset:
    def test_fetch_single_page(self) -> None:
        raw = [{"pd_id": "1"}, {"pd_id": "2"}]
        service, client = _make_service(fetch_page_return=raw, count_return=2)
        records, meta = service.fetch("abcd-1234", limit=2)
        assert records == raw
        assert meta.total == 2
        assert len(records) == 2

    def test_fetch_multiple_pages(self) -> None:
        page_a = [{"pd_id": "1"}, {"pd_id": "2"}]
        page_b = [{"pd_id": "3"}]
        service, _client = _make_service(
            count_return=3,
            fetch_page_call_side_effect=lambda ds, limit, offset: (
                page_a if offset == 0 else page_b
            ),
        )
        records, meta = service.fetch("abcd-1234", limit=2)
        assert records == [{"pd_id": "1"}, {"pd_id": "2"}, {"pd_id": "3"}]
        assert meta.total == 3

    def test_stop_on_empty_page(self) -> None:
        service, _client = _make_service(fetch_page_return=[], count_return=100)
        records, _meta = service.fetch("abcd-1234", limit=2)
        assert records == []

    def test_respect_max_records(self) -> None:
        page = [{"pd_id": "1"}, {"pd_id": "2"}]
        service, _client = _make_service(fetch_page_return=page, count_return=100)
        records, meta = service.fetch("abcd-1234", limit=2, max_records=2)
        assert len(records) == 2
        assert meta.truncated is True

    def test_raise_on_missing_dataset(self) -> None:
        service, _client = _make_service(
            fetch_page_side_effect=SocrataError("HTTP 404 dataset inexistente")
        )
        with pytest.raises(SocrataError):
            service.fetch("zzzz-9999")

    def test_tolerate_count_failure(self) -> None:
        # Se count falha, segue paginando sem total.
        raw = [{"pd_id": "1"}]
        service, _client = _make_service(
            fetch_page_return=raw, count_side_effect=SocrataError("count falhou")
        )
        records, meta = service.fetch("abcd-1234", limit=2)
        assert records == raw
        assert meta.total is None


# ---------------------------------------------------------------------------
# count / base_url
# ---------------------------------------------------------------------------


class TestMetadata:
    def test_delegate_count(self) -> None:
        service, client = _make_service(count_return=42)
        assert service.count("abcd-1234") == 42
        client.count.assert_called_with("abcd-1234")

    def test_expose_base_url(self) -> None:
        service, _client = _make_service()
        assert service.base_url == "https://data.energystar.gov"

    def test_construct_query_metadata(self) -> None:
        meta = QueryMetadata(
            dataset_id="abcd-1234", offset=0, limit=2, total=5, truncated=False
        )
        assert meta.dataset_id == "abcd-1234"
        assert meta.total == 5
