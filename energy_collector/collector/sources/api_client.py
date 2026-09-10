"""Infraestrutura mínima compartilhada para clientes HTTP de fontes."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

import requests


class ApiDataClient(ABC):
    """Base de transporte; parsing permanece específico no adapter da fonte."""

    def __init__(self, *, timeout: float = 30.0, session: Any = requests) -> None:
        self.timeout = timeout
        self._session = session

    def get_text(self, url: str) -> str:
        response = self._session.get(url, timeout=self.timeout)
        response.raise_for_status()
        return response.text

    @abstractmethod
    def _fetch_rows(self) -> list[dict[str, Any]]:
        """Transporta e transforma o payload em registros crus da fonte."""
        raise NotImplementedError
