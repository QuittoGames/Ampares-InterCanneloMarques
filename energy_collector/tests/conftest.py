"""Fixtures e helpers compartilhados dos testes unitarios.

Nada aqui toca rede ou banco reais: o pool falso e um ``MagicMock`` com os
context managers que ``collector.database`` espera, e o isolamento de
ambiente e feito com snapshot/restore manual de ``os.environ`` (o
``load_dotenv`` muta ``os.environ`` diretamente, fora do alcance do
``monkeypatch``).
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from decimal import Decimal
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from collector.models import SOURCE_NAME, Product

#: Chaves de ambiente lidas pelo coletor — isoladas nos testes de config.
ENV_KEYS = (
    "DB_HOST",
    "DB_USERNAME",
    "DB_PASSWORD",
    "DATABASE",
    "DB_PORT",
    "DB_SSLMODE",
    "SOCRATA_APP_TOKEN",
)


def make_product(
    *,
    name: str | None = "Generic Product",
    brand: str | None = "ACME",
    model: str | None = "X-1",
    category: str = "refrigerators",
    subcategory: str = "Geladeira",
    power: Decimal | None = None,
    annual: Decimal | None = None,
    source_id: str | None = "SRC-1",
    dataset_category: str | None = None,
) -> Product:
    """Constroi um ``Product`` direto pelo contrato publico do dataclass."""
    return Product(
        name=name,
        brand=brand,
        model=model,
        category=category,
        subcategory=subcategory,
        avg_power_w=power,
        annual_energy_kwh=annual,
        source=SOURCE_NAME,
        source_id=source_id,
        dataset_category=dataset_category,
    )


def make_fake_pool(existing: int = 0) -> tuple[MagicMock, MagicMock, MagicMock]:
    """Retorna ``(pool, conn, cursor)`` falsos para ``collector.database``.

    ``existing`` e o valor retornado pelo pre-count
    (``SELECT count(*) ... WHERE id = ANY(...)``).
    """
    pool = MagicMock(name="fake_pool")
    conn = MagicMock(name="fake_conn")
    cursor = MagicMock(name="fake_cursor")
    pool.connection.return_value.__enter__.return_value = conn
    conn.transaction.return_value.__enter__.return_value = None
    conn.cursor.return_value.__enter__.return_value = cursor
    conn.execute.return_value.fetchone.return_value = (existing,)
    return pool, conn, cursor


@pytest.fixture
def isolated_env() -> Iterator[None]:
    """Limpa as chaves do coletor de ``os.environ`` e restaura ao final.

    Snapshot/restore manual porque ``load_dotenv`` escreve em
    ``os.environ`` por conta propria — ``monkeypatch`` nao desfaz isso.
    """
    saved = {key: os.environ.get(key) for key in ENV_KEYS}
    for key in ENV_KEYS:
        os.environ.pop(key, None)
    try:
        yield
    finally:
        for key in ENV_KEYS:
            if saved[key] is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = saved[key]  # type: ignore[assignment]


def write_env(path: Path, values: dict[str, str]) -> Path:
    """Escreve um arquivo .env sintetico em ``path``."""
    path.write_text(
        "\n".join(f"{key}={value}" for key, value in values.items()) + "\n",
        encoding="utf-8",
    )
    return path
