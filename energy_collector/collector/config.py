"""Configuracao do coletor: credenciais de banco, constantes Socrata e
catalogo de datasets elegiveis.

Decisoes da spec refletidas aqui:

* Credenciais lidas EXCLUSIVAMENTE do ``.env`` do projeto servidor
  (raiz do projeto Java pai). Tres estilos suportados (FR-008, A6):

  1. **DB_URL** (preferido, novo estilo): URI completa
     ``postgresql://user:senha@host:port/db?sslmode=require``. Quando a
     senha tem caracteres especiais (ex.: ``@``), ela deve vir
     percent-encoded na URI (``@`` -> ``%40``) — recomendacao oficial do
     Supabase. O coletor decodifica e re-encoda com seguranca.
  2. **DATABASE_URL** (legacy/alt name): mesma URI que ``DB_URL``,
     mantido para compatibilidade com configuracoes existentes.
  3. **Chaves discretas** (legado, ja presente no .env atual):
     ``DB_HOST``, ``DB_USERNAME``, ``DB_PASSWORD``, ``DB_PORT``,
     ``DATABASE``, ``DB_SSLMODE``. O coletor monta a URI internamente
     com a senha percent-encoded — o usuario nao precisa editar o .env.

* Seguranca: a senha nunca aparece em ``repr``/logs (``field(repr=False)``).
* Consumidor anonimo do Socrata (A5): ``SOCRATA_APP_TOKEN`` e OPCIONAL.
* Datasets CONHECIDOS tem mapeamento verificado (``KNOWN_DATASETS``);
  desconhecidos usam extracao heuristica em ``normalization`` (FR-012).

Nota sobre o driver: usamos **psycopg 3** (nao psycopg2) porque o pool
multi-thread do design (``psycopg_pool``) e necessario para a performance
alvo; ``psycopg.connect`` aceita a mesma ``conninfo``/DATABASE_URL do
psycopg2, entao a URI do snippet do Supabase funciona igual.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse

from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Constantes da API publica ENERGY STAR (Socrata)
# ---------------------------------------------------------------------------

#: Base da API de dados (SoQL) — acesso anonimo, sem token obrigatorio.
SOCRATA_BASE: str = "https://data.energystar.gov"

#: Endpoint do Catalog API usado para descoberta automatica de datasets.
CATALOG_URL: str = "https://api.us.socrata.com/api/catalog/v1"

#: Caminho padrao do .env do projeto servidor (raiz do projeto Java pai).
#: config.py -> collector/ -> energy_collector/ -> <raiz do projeto>/.env
DEFAULT_ENV_PATH: Path = Path(__file__).resolve().parent.parent.parent / ".env"

#: Nome do arquivo de estado de retomada da varredura (git-ignorado).
STATE_FILE: str = ".collector_state.json"

#: Padrao de ID 4x4 do Socrata (ex.: "p5st-her9").
RE_4X4: re.Pattern[str] = re.compile(r"^[a-z0-9]{4}-[a-z0-9]{4}$")

#: sslmodes validos do libpq/psycopg.
_VALID_SSLMODES = frozenset(
    {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
)

#: aliases tratados como "exigir TLS" (o .env legado usa DB_SSLMODE=true).
_SSL_TRUE_ALIASES = frozenset({"true", "1", "yes", "on", "require"})

# ---------------------------------------------------------------------------
# Datasets conhecidos: mapeamento verificado de campos
# ---------------------------------------------------------------------------

KNOWN_DATASETS: dict[str, dict[str, str | None]] = {
    "p5st-her9": {  # ENERGY STAR Certified Residential Refrigerators
        "category": "refrigerators",
        "brand": "brand_name",
        "model": "model_number",
        "annual": "annual_energy_use_kwh_yr",
        "power": None,
    },
    "pd96-rr3d": {  # ENERGY STAR Certified Televisions
        "category": "televisions",
        "brand": "brand_name",
        "model": "model_name",
        "annual": "reported_annual_energy_consumption_kwh",
        "power": "power_consumption_in_on_mode_watts",
    },
    "rxdj-2c88": {  # ENERGY STAR Certified Computers
        "category": "computers",
        "brand": "brand_name",
        "model": "model_name",
        "annual": "tec_of_model_kwh",
        "power": None,
    },
    "bghd-e2wd": {  # ENERGY STAR Certified Residential Clothes Washers
        "category": "clothes_washers",
        "brand": "brand_name",
        "model": "model_number",
        "annual": "annual_energy_use_kwh_year",
        "power": None,
    },
}

#: Tarifa de energia em moeda/kWh usada nos calculos de custo derivado.
#: O normalizer NUNCA assume valor arbitrario: quando ausente, o custo
#: derivado fica ``None``. Pode ser sobrescrita por config/parametro.
DEFAULT_TARIFF_PER_KWH: Decimal | None = None


def map_sslmode(raw: str | None) -> str:
    """Traduz ``DB_SSLMODE`` do .env legado para um sslmode valido do psycopg."""
    if not raw:
        return "require"
    value = raw.strip().lower()
    if value in _SSL_TRUE_ALIASES:
        return "require"
    if value == "false":
        return "disable"
    if value in _VALID_SSLMODES:
        return value
    return "require"


@dataclass(frozen=True, slots=True)
class DbConfig:
    """Configuracao imutavel de conexao com o PostgreSQL (Supabase).

    Espelha as chaves do .env do projeto servidor (FR-008, A6). A senha
    fica fora de ``repr``/``str`` para nunca vazar em log (revisao de
    seguranca R3). A conexao efetiva usa :attr:`conninfo` (URI estilo
    DATABASE_URL com senha percent-encoded — seguro para caracteres
    especiais como ``@``).
    """

    host: str
    port: int
    username: str
    password: str = field(repr=False, compare=False)
    database: str = "postgres"
    sslmode: str = "require"

    # ------------------------------------------------------------------ #
    # URI de conexao (estilo DATABASE_URL, Supabase-safe)
    # ------------------------------------------------------------------ #
    @property
    def conninfo(self) -> str:
        """URI ``postgresql://...`` com senha percent-encoded.

        O ``@`` da senha vira ``%40`` etc., entao a URI nao quebra no
        separador userinfo/host. ``sslmode=require`` e sempre incluido
        para o Supabase.
        """
        pwd = quote(self.password, safe="")
        user = quote(self.username, safe="")
        db = quote(self.database, safe="")
        return (
            f"postgresql://{user}:{pwd}@{self.host}:{self.port}/{db}"
            f"?sslmode={self.sslmode}"
        )

    @classmethod
    def from_url(cls, url: str) -> "DbConfig":
        """Constroi a config a partir de uma ``DATABASE_URL`` completa.

        A senha pode vir percent-encoded na URI; aqui ela e decodificada
        para armazenamento e re-encodada em :attr:`conninfo` (round-trip
        seguro). ``sslmode`` ausente na URI => ``require``.
        """
        parsed = urlparse(url.strip())
        if not parsed.hostname:
            raise RuntimeError(f"DATABASE_URL invalido (sem host): {url!r}")
        query_sslmode = parse_qs(parsed.query).get("sslmode", [None])[0]
        sslmode = map_sslmode(query_sslmode) if query_sslmode else "require"
        password = unquote(parsed.password) if parsed.password else ""
        return cls(
            host=parsed.hostname,
            port=parsed.port or 5432,
            username=parsed.username or "postgres",
            password=password,
            database=parsed.path.lstrip("/") or "postgres",
            sslmode=sslmode,
        )

    # ------------------------------------------------------------------ #
    # Fabrica principal: .env do projeto pai
    # ------------------------------------------------------------------ #
    @classmethod
    def from_env(cls, path: Path = DEFAULT_ENV_PATH) -> "DbConfig":
        """Constroi a configuracao a partir do .env do projeto pai.

        Ordem de precedencia:
        1. ``DATABASE_URL`` (estilo Supabase) — se presente, usa direto.
        2. Chaves discretas ``DB_HOST``/``DB_USERNAME``/``DB_PASSWORD``/
           ``DB_PORT``/``DATABASE``/``DB_SSLMODE`` — monta a URI
           internamente com a senha percent-encoded.

        Falha RAPIDO com mensagem clara se o arquivo estiver ausente ou
        com chave obrigatoria faltando (edge case da spec).
        """
        if not path.exists():
            raise RuntimeError(
                f"Arquivo de ambiente nao encontrado: {path}. "
                "Esperado o .env do projeto Java com DATABASE_URL ou as "
                "chaves DB_HOST/DB_USERNAME/DB_PASSWORD/DATABASE."
            )

        load_dotenv(path, override=False)
        local_env = path.parent / "energy_collector" / ".env"
        if local_env.exists():
            load_dotenv(local_env, override=True)

        # (1) DB_URL wins — estilo Supabase, nome de variavel simplificado.
        database_url = os.getenv("DB_URL")
        if not database_url or not database_url.strip():
            # (1b) fallback: DATABASE_URL (legacy/alt name)
            database_url = os.getenv("DATABASE_URL")
        if database_url and database_url.strip():
            return cls.from_url(database_url)

        # (2) Chaves discretas legadas (o .env atual do projeto).
        def _get(key: str) -> str | None:
            value = os.getenv(key)
            if value is None:
                return None
            value = value.strip().strip("\r")
            return value or None

        host = _get("DB_HOST")
        username = _get("DB_USERNAME")
        password = _get("DB_PASSWORD")
        database = _get("DATABASE")
        port_raw = _get("DB_PORT") or "5432"
        sslmode = map_sslmode(_get("DB_SSLMODE"))

        missing = [
            name
            for name, value in (
                ("DB_HOST", host),
                ("DB_USERNAME", username),
                ("DB_PASSWORD", password),
                ("DATABASE", database),
            )
            if not value
        ]
        if missing:
            raise RuntimeError(
                "Chaves obrigatorias ausentes no .env (e DATABASE_URL nao "
                "definido): " + ", ".join(missing)
            )

        try:
            port = int(port_raw)
        except ValueError as exc:
            raise RuntimeError(f"DB_PORT invalido: {port_raw!r}") from exc

        return cls(
            host=host or "",
            port=port,
            username=username or "",
            password=password or "",
            database=database or "postgres",
            sslmode=sslmode,
        )

    def psycopg_kwargs(self) -> dict[str, object]:
        """Kwargs alternativos para psycopg.connect (mantido por flexibilidade).

        Para o pool multi-thread use :attr:`conninfo` (passado como
        ``conninfo=`` no ``ConnectionPool``). Este metodo fica disponivel
        para conexoes pontuais/diagnosticas.
        """
        return {
            "host": self.host,
            "port": self.port,
            "dbname": self.database,
            "user": self.username,
            "password": self.password,
            "sslmode": self.sslmode,
            "connect_timeout": 15,
            "application_name": "energy-collector",
        }


def get_app_token() -> str | None:
    """Retorna o token Socrata opcional (``SOCRATA_APP_TOKEN``) ou None."""
    token = os.getenv("SOCRATA_APP_TOKEN")
    return token.strip() if token and token.strip() else None
