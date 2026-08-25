"""Cliente HTTP para a API publica ENERGY STAR (Socrata/OpenData).

Decisoes da spec refletidas aqui:

* Consumidor ANONIMO (A5, FR-001): nenhum cadastro/token obrigatorio.
  ``SOCRATA_APP_TOKEN`` e opcional e apenas eleva o teto de requisicoes.
* Boa convivencia com API publica (revisao R4): rate limiter compartilhado
  entre instancias (token-bucket de espacamento simples) e ``User-Agent``
  identificavel. Cada instancia tem sua propria ``requests.Session`` —
  crie UM cliente por thread (Session nao e thread-safe).
* Tolerancia a falhas transitorias (FR-009): retries com recuo exponencial
  (teto 60s) para rede/5xx; para HTTP 429 respeita ``Retry-After`` com
  CLAMP de 120s (R5: "nunca abortar" != retry infinito). Ao esgotar as
  tentativas, levanta :class:`SocrataError` e o chamador isola o dataset.
* Descoberta automatica (FR-001): Catalog API lista os datasets 4x4 de
  produtos certificados; metadatasets/indices sao filtrados fora (A1).
* Paginacao estavel (FR-002): ``$order=:id`` (campo de sistema presente
  em TODO dataset Socrata — mais universal que ``pd_id``).
"""

from __future__ import annotations

import json
import logging
import threading
import time
from typing import Any

import requests

from .config import CATALOG_URL, SOCRATA_BASE

logger = logging.getLogger(__name__)

#: User-Agent identificavel (boa pratica em API publica, R4).
USER_AGENT = "energy-collector/1.0 (+https://github.com/QuittoGames)"

#: Clamp maximo para Retry-After (R5) e teto do backoff exponencial.
MAX_RETRY_AFTER_S = 120
MAX_BACKOFF_S = 60

#: Padrao de nome que identifica datasets de produtos certificados (A1).
_PRODUCT_NAME_MARK = "energy star certified"


class SocrataError(Exception):
    """Falha irrecuperavel de HTTP/parse apos esgotar as tentativas."""


class RateLimiter:
    """Espacamento minimo entre requisicoes, compartilhavel entre threads.

    Token-bucket simplificado: garante no maximo ``rate_per_sec``
    requisicoes/segundo NO AGREGADO de todas as threads que o compartilham
    (R4: evita rajadas que levam a throttle/ban do IP anonimo).
    """

    def __init__(self, rate_per_sec: float = 4.0) -> None:
        if rate_per_sec <= 0:
            raise ValueError("rate_per_sec deve ser > 0")
        self._min_interval = 1.0 / rate_per_sec
        self._lock = threading.Lock()
        self._next_at = 0.0

    def acquire(self) -> None:
        """Bloqueia ate liberar o proximo slot de requisicao."""
        with self._lock:
            now = time.monotonic()
            wait = max(0.0, self._next_at - now)
            self._next_at = max(now, self._next_at) + self._min_interval
        if wait > 0:
            time.sleep(wait)


class SocrataClient:
    """Cliente da API Socrata do ENERGY STAR (anonimo por padrao).

    NAO compartilhe uma instancia entre threads — crie uma por thread e
    compartilhe apenas o :class:`RateLimiter`.
    """

    def __init__(
        self,
        app_token: str | None = None,
        base_url: str = SOCRATA_BASE,
        catalog_url: str = CATALOG_URL,
        timeout: float = 60.0,
        max_retries: int = 6,
        rate_limiter: RateLimiter | None = None,
    ) -> None:
        self.app_token = app_token
        self.base_url = base_url.rstrip("/")
        self.catalog_url = catalog_url
        self.timeout = timeout
        self.max_retries = max_retries
        self.rate_limiter = rate_limiter
        self._session = requests.Session()

    # ------------------------------------------------------------------ #
    # Context manager
    # ------------------------------------------------------------------ #
    def __enter__(self) -> "SocrataClient":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    def close(self) -> None:
        """Fecha a sessao HTTP interna."""
        try:
            self._session.close()
        except Exception:  # noqa: BLE001 - fechamento nunca quebra o caller
            logger.debug("Falha ao fechar sessao HTTP", exc_info=True)

    # ------------------------------------------------------------------ #
    # Headers / transporte
    # ------------------------------------------------------------------ #
    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/json", "User-Agent": USER_AGENT}
        if self.app_token:
            headers["X-App-Token"] = self.app_token
        return headers

    def _throttle(self) -> None:
        if self.rate_limiter is not None:
            self.rate_limiter.acquire()

    def _sleep(self, attempt: int, retry_after: str | None) -> None:
        """Backoff exponencial com teto; Retry-After respeitado com clamp."""
        if retry_after and retry_after.strip().isdigit():
            delay = min(max(int(retry_after), 1), MAX_RETRY_AFTER_S)
        else:
            delay = min(2.0**attempt, float(MAX_BACKOFF_S))
        time.sleep(delay)

    def _request(self, url: str, params: dict[str, Any]) -> Any:
        """GET com retry/backoff; retorna o corpo JSON parseado."""
        last_error: Exception | None = None
        for attempt in range(1, self.max_retries + 1):
            self._throttle()
            try:
                resp = self._session.get(
                    url, params=params, headers=self._headers(), timeout=self.timeout
                )
            except requests.RequestException as exc:
                last_error = exc
                logger.warning(
                    "Erro de rede (tentativa %d/%d): %s",
                    attempt,
                    self.max_retries,
                    exc,
                )
                self._sleep(attempt, None)
                continue

            if resp.status_code == 200:
                try:
                    return resp.json()
                except (json.JSONDecodeError, ValueError) as exc:
                    raise SocrataError(f"Corpo JSON invalido de {url}: {exc}") from exc

            if resp.status_code in (429, 500, 502, 503, 504):
                logger.warning(
                    "HTTP %s em %s (tentativa %d/%d) — backoff",
                    resp.status_code,
                    url,
                    attempt,
                    self.max_retries,
                )
                self._sleep(attempt, resp.headers.get("Retry-After"))
                last_error = SocrataError(f"HTTP {resp.status_code}")
                continue

            raise SocrataError(f"HTTP {resp.status_code} em {url}: {resp.text[:200]}")

        raise SocrataError(
            f"Tentativas esgotadas ({self.max_retries}) para {url}: {last_error}"
        )

    # ------------------------------------------------------------------ #
    # API publica
    # ------------------------------------------------------------------ #
    def fetch_page(
        self, dataset_id: str, limit: int, offset: int
    ) -> list[dict[str, Any]]:
        """Busca uma pagina de registros brutos (``$order=:id`` estavel)."""
        url = f"{self.base_url}/resource/{dataset_id}.json"
        params = {"$limit": limit, "$offset": offset, "$order": ":id"}
        data = self._request(url, params)
        if not isinstance(data, list):
            raise SocrataError(
                f"Esperado array JSON em {dataset_id}, veio {type(data).__name__}"
            )
        return data

    def count(self, dataset_id: str) -> int:
        """Total de registros do dataset (``$select=count(*)``)."""
        url = f"{self.base_url}/resource/{dataset_id}.json"
        data = self._request(url, {"$select": "count(*)"})
        try:
            return int(data[0]["count"])
        except (IndexError, KeyError, TypeError, ValueError) as exc:
            raise SocrataError(f"Resposta inesperada de count({dataset_id})") from exc

    def discover(self, only_product_datasets: bool = True) -> list[tuple[str, str]]:
        """Lista ``(dataset_id, nome)`` dos datasets de produtos certificados.

        Filtra metadatasets/indices pelo marcador "ENERGY STAR Certified"
        no titulo (A1). Resultado ordenado por nome para varredura reprodutivel.
        """
        params = {
            "domains": "data.energystar.gov",
            "search_context": "data.energystar.gov",
            "only": "datasets",
            "limit": 200,
        }
        data = self._request(self.catalog_url, params)
        out: list[tuple[str, str]] = []
        for item in data.get("results", []):
            resource = item.get("resource", {})
            ds_id = resource.get("id")
            name = resource.get("name") or ""
            if not ds_id:
                continue
            if only_product_datasets and _PRODUCT_NAME_MARK not in name.casefold():
                continue
            out.append((ds_id, name.strip()))
        out.sort(key=lambda t: t[1])
        return out
