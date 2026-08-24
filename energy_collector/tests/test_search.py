from collector.api_client import SocrataClient
from collector.services.collection import CollectionService


class FakeClient(SocrataClient):
    """In-memory client: one valid record then empty page."""

    def __init__(self):
        super().__init__("https://example.test")

    def fetch_page(self, dataset_id, offset, limit):
        if offset == 0:
            return [
                {
                    "pd_id": "1",
                    "brand_name": "A",
                    "model_number": "M1",
                    "annual_energy_use_kwh_yr": "100",
                }
            ]
        return []

    def discover_dataset_id(self, query):
        return "fake-id"


def test_process_filters_invalid():
    service = CollectionService(client=None, conn=None)
    raw = [
        {
            "pd_id": "1",
            "brand_name": "A",
            "model_number": "M1",
            "annual_energy_use_kwh_yr": "-5",
        },
        {
            "pd_id": "2",
            "brand_name": "B",
            "model_number": "M2",
            "annual_energy_use_kwh_yr": "50",
        },
    ]
    results = [p for p in (service._process(r, "refrigerators") for r in raw) if p]
    assert len(results) == 1
    assert results[0].brand == "B"
    assert results[0].annual_energy_kwh == 50.0


def test_fetch_category_fetches_raw_records():
    service = CollectionService(client=FakeClient(), conn=None)
    raw = service.fetch_category("refrigerators", limit=10, page_size=10)
    assert len(raw) == 1
    assert raw[0]["pd_id"] == "1"
