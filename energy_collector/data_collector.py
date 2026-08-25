"""Entrypoint CLI do Energy Collector (ENERGY STAR → PostgreSQL/Supabase).

Varre o catalogo publico ENERGY STAR (Socrata, acesso anonimo) e povoa a
tabela ``product`` do banco do projeto Java. Este modulo so faz parsing
de argumentos, montagem das dependencias e relatorio: o pipeline vive em
:class:`collector.services.collection.CollectionService`.

Exemplos::

    python data_collector.py --all                      # varredura completa
    python data_collector.py --category refrigerators   # uma categoria
    python data_collector.py --all --resume             # retoma interrompida
    python data_collector.py --category p5st-her9 --limit 100  # smoke test
    python data_collector.py --all --sequential         # baseline debug

Modos (FR-007, SC-003): concorrente (padrao: 8 produtores x 4 escritoras)
ou sequencial (--sequential).
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

from collector.api_client import RateLimiter, SocrataClient, SocrataError
from collector.config import (
    DEFAULT_ENV_PATH,
    KNOWN_DATASETS,
    RE_4X4,
    STATE_FILE,
    DbConfig,
    get_app_token,
)
from collector.database import close_pool, create_pool, ensure_table
from collector.normalization import slugify_category
from collector.services.collection import CollectionReport, CollectionService

LOG = logging.getLogger("data_collector")

#: Log ancorado no diretorio do projeto (NUNCA no CWD — revisao R2).
LOG_FILE = Path(__file__).resolve().parent / "data_collector.log"


def setup_logging() -> None:
    """Console em INFO + arquivo rotativo em DEBUG, ancorado no projeto."""
    LOG.setLevel(logging.DEBUG)
    fmt = logging.Formatter("%(asctime)s %(levelname)-5s %(message)s")

    console = logging.StreamHandler(sys.stdout)
    console.setLevel(logging.INFO)
    console.setFormatter(fmt)
    LOG.addHandler(console)

    file_handler = RotatingFileHandler(
        LOG_FILE, maxBytes=5_000_000, backupCount=3, encoding="utf-8"
    )
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(fmt)
    LOG.addHandler(file_handler)

    # Propaga logs dos submodulos (client, service, database) para os handlers.
    for name in ("collector",):
        logging.getLogger(name).setLevel(logging.DEBUG)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Coletor ENERGY STAR (Socrata) → PostgreSQL/Supabase"
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--category", help="categoria logica ou ID 4x4 de dataset")
    group.add_argument("--all", action="store_true", help="varre todo o catalogo")
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="teto de registros por dataset (smoke tests; desativa resume)",
    )
    parser.add_argument(
        "--page-size", type=int, default=1000, help="registros por pagina Socrata"
    )
    parser.add_argument("--resume", action="store_true", help="retoma do estado salvo")
    parser.add_argument(
        "--sequential", action="store_true", help="modo sequencial (debug/baseline)"
    )
    parser.add_argument(
        "--fetch-workers",
        type=int,
        default=8,
        help="threads produtoras (datasets em paralelo)",
    )
    parser.add_argument(
        "--db-workers", type=int, default=4, help="threads escritoras no PostgreSQL"
    )
    parser.add_argument(
        "--rate", type=float, default=4.0, help="requisicoes/segundo agregado (anonimo)"
    )
    parser.add_argument(
        "--env-file", type=Path, default=DEFAULT_ENV_PATH, help="caminho do .env"
    )
    parser.add_argument(
        "--state-file", type=Path, default=Path(STATE_FILE), help="arquivo de retomada"
    )
    return parser


def _resolve_single(
    service: CollectionService, probe: SocrataClient, category_arg: str
) -> dict[str, str]:
    """Resolve --category para ``{dataset_id: categoria_logica}``.

    Aceita ID 4x4 direto ou nome de categoria (conhecida ou slug do titulo
    descoberto no catalogo).
    """
    if RE_4X4.match(category_arg):
        known = KNOWN_DATASETS.get(category_arg)
        category = (known or {}).get("category") or "custom"
        return {category_arg: category}

    wanted = category_arg.casefold()
    for dataset_id, name in probe.discover():
        known = KNOWN_DATASETS.get(dataset_id)
        logical = (known or {}).get("category") or slugify_category(name)
        if wanted in (logical.casefold(), slugify_category(name)):
            return {dataset_id: logical}

    available = sorted(
        {(k.get("category") or "") for k in KNOWN_DATASETS.values()} - {""}
    )
    raise SystemExit(
        f"Categoria '{category_arg}' nao encontrada. "
        f"Conhecidas: {', '.join(available)}; ou passe o ID 4x4 do dataset."
    )


def _log_report(report: CollectionReport, elapsed_s: float) -> None:
    LOG.info("=" * 78)
    LOG.info(
        "%-28s %-11s %9s %9s %9s %11s  %s",
        "categoria",
        "dataset",
        "recebidos",
        "inseridos",
        "atualiz.",
        "descartados",
        "status",
    )
    for cat in report.per_category:
        LOG.info(
            "%-28s %-11s %9d %9d %9d %11d  %s",
            cat.category[:28],
            cat.dataset_id,
            cat.received,
            cat.inserted,
            cat.updated,
            cat.discarded,
            cat.status,
        )
    totals = report.totals
    LOG.info("-" * 78)
    LOG.info(
        "TOTAL: recebidos=%d inseridos=%d atualizados=%d descartados=%d | %.1fs",
        totals.received,
        totals.inserted,
        totals.updated,
        totals.discarded,
        elapsed_s,
    )


def main(argv: list[str] | None = None) -> int:
    """Ponto de entrada do coletor. 0 = sucesso; 2 = uso; 1 = falha."""
    setup_logging()
    args = build_parser().parse_args(argv)

    if not args.category and not args.all:
        LOG.error("Nada a fazer: informe --category <nome|4x4> ou --all")
        return 2

    try:
        config = DbConfig.from_env(args.env_file)
    except RuntimeError as exc:
        LOG.error("%s", exc)
        return 1

    if config.username.strip().lower() == "postgres":
        LOG.warning(
            "Conectando como superusuario 'postgres'. Recomendado: role dedicado "
            "com privilegio minimo (ver docs/TODO.md, secao Human)."
        )

    token = get_app_token()
    LOG.info(
        "Socrata: %s | rate limit: %.1f req/s",
        "com app token" if token else "anonimo",
        args.rate,
    )
    limiter = RateLimiter(rate_per_sec=args.rate)
    make_client = lambda: SocrataClient(app_token=token, rate_limiter=limiter)  # noqa: E731

    try:
        pool = create_pool(config, max_size=args.db_workers + 2)
    except RuntimeError as exc:
        LOG.error("%s", exc)
        return 1

    started = time.monotonic()
    try:
        ensure_table(pool)
        service = CollectionService(
            make_client=make_client,
            pool=pool,
            state_path=args.state_file,
            page_size=args.page_size,
        )

        if args.category:
            with make_client() as probe:
                service.datasets = _resolve_single(service, probe, args.category)

        if args.sequential:
            report = service.run_sequential(resume=args.resume, limit=args.limit)
        else:
            report = service.run_concurrent(
                fetch_workers=args.fetch_workers,
                db_workers=args.db_workers,
                resume=args.resume,
                limit=args.limit,
            )

        _log_report(report, time.monotonic() - started)
        return 0 if report.totals.status != "partial" else 1
    except SocrataError as exc:
        LOG.error("Erro fatal da API: %s", exc)
        return 1
    except KeyboardInterrupt:
        LOG.warning("Interrompido pelo usuario — use --resume para continuar")
        return 130
    except Exception as exc:  # noqa: BLE001 - guarda final, nunca sai em silencio
        LOG.exception("Erro inesperado: %s", exc)
        return 1
    finally:
        close_pool(pool)


if __name__ == "__main__":
    raise SystemExit(main())
