"""Testes unitarios de ``collector.config``.

Cobre ``map_sslmode``, ``DbConfig.from_env``, ``psycopg_kwargs``,
``get_app_token`` e ``RE_4X4``. Toda leitura de ambiente usa arquivos
``.env`` sinteticos em ``tmp_path`` — o ``.env`` real do projeto pai nunca
e tocado.
"""

from __future__ import annotations

import pytest

from collector.config import DbConfig, RE_4X4, get_app_token, map_sslmode

from .conftest import write_env  # noqa: TID252 - helper do pacote de testes

BASE_ENV: dict[str, str] = {
    "DB_HOST": "db.supabase.co",
    "DB_USERNAME": "postgres",
    "DB_PASSWORD": "s3cret",
    "DATABASE": "postgres",
}


class TestMapSslmode:
    @pytest.mark.parametrize(
        "raw",
        ["true", "TRUE", " True ", "1", "yes", "YES", "on", "require", "REQUIRE"],
    )
    def should_map_true_aliases_to_require(self, raw: str) -> None:
        assert map_sslmode(raw) == "require"

    @pytest.mark.parametrize("raw", ["false", "FALSE", " False "])
    def should_map_false_to_disable(self, raw: str) -> None:
        assert map_sslmode(raw) == "disable"

    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("disable", "disable"),
            ("allow", "allow"),
            ("prefer", "prefer"),
            ("verify-ca", "verify-ca"),
            ("verify-full", "verify-full"),
            ("VERIFY-FULL", "verify-full"),  # case-insensitive passthrough
        ],
    )
    def should_pass_through_valid_libpq_modes(self, raw: str, expected: str) -> None:
        assert map_sslmode(raw) == expected

    @pytest.mark.parametrize("raw", [None, "", "   ", "bogus", "required", "0"])
    def should_default_to_require_when_absent_or_unknown(self, raw: str | None) -> None:
        assert map_sslmode(raw) == "require"


class TestRe4x4:
    @pytest.mark.parametrize("dataset_id", ["p5st-her9", "abcd-1234", "0000-zzzz"])
    def should_match_valid_4x4_ids(self, dataset_id: str) -> None:
        assert RE_4X4.match(dataset_id)

    @pytest.mark.parametrize(
        "dataset_id",
        [
            "P5ST-HER9",  # maiusculas nao casam
            "abcde-fghi",  # 5x4
            "abc-def",  # 3x3
            "p5st_her9",  # separador errado
            "p5st-her9-extra",  # sufixo
            "",
        ],
    )
    def should_reject_invalid_ids(self, dataset_id: str) -> None:
        assert RE_4X4.match(dataset_id) is None


@pytest.mark.usefixtures("isolated_env")
class TestFromEnv:
    def should_raise_when_env_file_is_missing(self, tmp_path) -> None:
        missing = tmp_path / "nao-existe.env"
        with pytest.raises(RuntimeError, match="nao encontrado"):
            DbConfig.from_env(missing)

    def should_load_full_config_with_defaults(self, tmp_path) -> None:
        env_file = write_env(tmp_path / ".env", dict(BASE_ENV))

        cfg = DbConfig.from_env(env_file)

        assert cfg.host == "db.supabase.co"
        assert cfg.port == 5432  # DB_PORT ausente -> default
        assert cfg.username == "postgres"
        assert cfg.password == "s3cret"
        assert cfg.database == "postgres"
        assert cfg.sslmode == "require"  # DB_SSLMODE ausente -> default seguro

    def should_strip_residual_spaces_from_env_values(self, tmp_path) -> None:
        # Aspas preservam os espacos internos para o dotenv; o _get deve
        # remover o residuo classico do .env legado ("DB_HOST= valor").
        env_file = write_env(
            tmp_path / ".env",
            {
                "DB_HOST": '"  host.com  "',
                "DB_USERNAME": '" user "',
                "DB_PASSWORD": '" pass "',
                "DATABASE": '" db "',
            },
        )

        cfg = DbConfig.from_env(env_file)

        assert (cfg.host, cfg.username, cfg.password, cfg.database) == (
            "host.com",
            "user",
            "pass",
            "db",
        )

    def should_use_explicit_port_and_map_sslmode_false(self, tmp_path) -> None:
        env_file = write_env(
            tmp_path / ".env",
            {**BASE_ENV, "DB_PORT": "6543", "DB_SSLMODE": "false"},
        )

        cfg = DbConfig.from_env(env_file)

        assert cfg.port == 6543
        assert cfg.sslmode == "disable"

    def should_list_all_missing_keys_in_error(self, tmp_path) -> None:
        env_file = write_env(tmp_path / ".env", {"DB_HOST": "db.supabase.co"})

        with pytest.raises(RuntimeError) as excinfo:
            DbConfig.from_env(env_file)

        message = str(excinfo.value)
        for missing in ("DB_USERNAME", "DB_PASSWORD", "DATABASE"):
            assert missing in message
        assert "DB_HOST" not in message.split(":", 1)[-1]

    def should_treat_empty_value_as_missing(self, tmp_path) -> None:
        env_file = write_env(tmp_path / ".env", {**BASE_ENV, "DB_PASSWORD": ""})

        with pytest.raises(RuntimeError, match="DB_PASSWORD"):
            DbConfig.from_env(env_file)

    def should_raise_on_invalid_port(self, tmp_path) -> None:
        env_file = write_env(tmp_path / ".env", {**BASE_ENV, "DB_PORT": "abc"})

        with pytest.raises(RuntimeError, match="DB_PORT"):
            DbConfig.from_env(env_file)

    def should_let_local_env_override_parent(self, tmp_path) -> None:
        parent = write_env(tmp_path / ".env", {**BASE_ENV, "DB_PORT": "5432"})
        local_dir = tmp_path / "energy_collector"
        local_dir.mkdir()
        write_env(
            local_dir / ".env",
            {"DB_HOST": "localhost", "DATABASE": "localdb"},
        )

        cfg = DbConfig.from_env(parent)

        assert cfg.host == "localhost"  # sobrescrito pelo .env local
        assert cfg.database == "localdb"
        assert cfg.username == "postgres"  # herdado do pai
        assert cfg.port == 5432

    def should_keep_password_out_of_repr(self, tmp_path) -> None:
        secret = "UNIQUE-S3cret-0987"
        env_file = write_env(tmp_path / ".env", {**BASE_ENV, "DB_PASSWORD": secret})

        cfg = DbConfig.from_env(env_file)

        assert cfg.password == secret  # acessivel como atributo...
        assert secret not in repr(cfg)  # ...mas nunca vaza em repr/log
        assert secret not in str(cfg)
        assert "db.supabase.co" in repr(cfg)

    def should_build_psycopg_kwargs_without_uri(self, tmp_path) -> None:
        env_file = write_env(tmp_path / ".env", dict(BASE_ENV))
        cfg = DbConfig.from_env(env_file)

        kwargs = cfg.psycopg_kwargs()

        assert kwargs == {
            "host": "db.supabase.co",
            "port": 5432,
            "dbname": "postgres",
            "user": "postgres",
            "password": "s3cret",
            "sslmode": "require",
            "connect_timeout": 15,
            "application_name": "energy-collector",
            "keepalives": 1,
            "keepalives_idle": 30,
            "keepalives_interval": 10,
            "keepalives_count": 5,
        }
        assert "conninfo" not in kwargs  # kwargs, nunca URI (senha com @)


@pytest.mark.usefixtures("isolated_env")
class TestGetAppToken:
    def should_return_none_when_unset(self) -> None:
        assert get_app_token() is None

    @pytest.mark.parametrize("raw", ["", "   "])
    def should_return_none_for_blank_values(self, raw: str, monkeypatch) -> None:
        monkeypatch.setenv("SOCRATA_APP_TOKEN", raw)
        assert get_app_token() is None

    def should_strip_and_return_token(self, monkeypatch) -> None:
        monkeypatch.setenv("SOCRATA_APP_TOKEN", "  tok-123  ")
        assert get_app_token() == "tok-123"
