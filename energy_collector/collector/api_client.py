"""Socrata / ENERGY STAR HTTP client with resilience built in.

Handles:
- fixed timeout
- exponential backoff retry on 429 / 5xx
- honours the upstream Retry-After header
- validates that the body is JSON
- never attempts to bypass rate limits
"""

from __future__ import annotations

import json
import logging
import time

import requests

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = 30
MAX_RETRIES = 5
BASE_BACKOFF = 2.0


class SocrataError(Exception):
    """Raised for unrecoverable HTTP / parsing failures."""


class SocrataClient:
    def __init__(
        self,
        base_url: str,
        app_token: str | None = None,
        timeout: int = DEFAULT_TIMEOUT,
        max_retries: int = MAX_RETRIES,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.app_token = app_token
        self.timeout = timeout
        self.max_retries = max_retries
        self._session = requests.Session()

    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/json"}
        if self.app_token:
            headers["X-App-Token"] = self.app_token
        return headers

    # ------------------------------------------------------------------ #
    # Low-level request with retry / backoff (shared by all callers)
    # ------------------------------------------------------------------ #
    def _request(self, url: str, params: dict) -> list[dict]:
        last_err: Exception | None = None
        for attempt in range(1, self.max_retries + 1):
            try:
                resp = self._session.get(
                    url, params=params, headers=self._headers(), timeout=self.timeout
                )
            except requests.RequestException as exc:
                last_err = exc
                logger.warning(
                    "Network error (attempt %d/%d): %s", attempt, self.max_retries, exc
                )
                self._backoff(attempt, None)
                continue

            if resp.status_code == 200:
                return self._parse(resp)

            if resp.status_code in (429, 500, 502, 503, 504):
                logger.warning(
                    "Retryable HTTP %s (attempt %d/%d)",
                    resp.status_code,
                    attempt,
                    self.max_retries,
                )
                self._backoff(attempt, resp.headers.get("Retry-After"))
                last_err = SocrataError(f"HTTP {resp.status_code}")
                continue

            raise SocrataError(
                f"Unrecoverable HTTP {resp.status_code}: {resp.text[:200]}"
            )

        raise SocrataError(f"Exhausted retries for {url}: {last_err}")

    # ------------------------------------------------------------------ #
    # Public helpers
    # ------------------------------------------------------------------ #
    def fetch_page(self, dataset_id: str, offset: int, limit: int) -> list[dict]:
        """Fetch a single page of records (limit/offset pagination)."""
        url = f"{self.base_url}/resource/{dataset_id}.json"
        params = {"$limit": limit, "$offset": offset, "$order": "pd_id"}
        return self._request(url, params)

    def discover_dataset_id(self, query: str) -> str | None:
        """Find a Socrata dataset id by searching the ENERGY STAR catalogue."""
        try:
            resp = self._session.get(
                f"{self.base_url}/api/catalog/v1",
                params={"q": query, "limit": 10},
                headers=self._headers(),
                timeout=self.timeout,
            )
        except requests.RequestException as exc:
            logger.warning("Catalog discovery failed for '%s': %s", query, exc)
            return None

        if resp.status_code != 200:
            logger.warning(
                "Catalog discovery HTTP %s for '%s'", resp.status_code, query
            )
            return None

        try:
            results = resp.json().get("results", [])
        except (json.JSONDecodeError, ValueError):
            return None

        for r in results:
            name = r.get("resource", {}).get("name", "")
            if "ENERGY STAR Certified" in name:
                return r.get("resource", {}).get("id")
        return None

    # ------------------------------------------------------------------ #
    # Internals
    # ------------------------------------------------------------------ #
    @staticmethod
    def _parse(resp: requests.Response) -> list[dict]:
        try:
            data = resp.json()
        except (json.JSONDecodeError, ValueError) as exc:
            raise SocrataError(f"Invalid JSON body: {exc}") from exc
        if not isinstance(data, list):
            raise SocrataError(f"Expected a JSON array, got {type(data).__name__}")
        return data

    def _backoff(self, attempt: int, retry_after: str | None) -> None:
        if retry_after and retry_after.isdigit():
            sleep_for = int(retry_after)
        else:
            sleep_for = BASE_BACKOFF**attempt
        logger.info("Backing off %.1fs before retry", sleep_for)
        time.sleep(sleep_for)
