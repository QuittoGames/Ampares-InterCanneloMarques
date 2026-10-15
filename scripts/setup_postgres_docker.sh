#!/usr/bin/env bash
# =============================================================================
# scripts/setup_postgres_docker.sh
#
# Deixa a instância PostgreSQL local do projeto (Docker) pronta e validada:
#   container saudável + schema (dump ou migrations) + dados + validação.
#
# Fonte da especificação:
#   .agents/specs/spec-docker-postgres-frontend-units.md — Task 1 (§1)
#
# CONTRATOS (spec §1 — fechados):
#   * Idempotente: container do projeto existente é REUTILIZADO (nunca
#     recriado, nunca parado). Container novo só é criado se não existir.
#   * Ordem canônica (§1.4):
#       Caminho A (dump em backups/*.dump, mais recente):
#         pg_restore -> create.sql -> 004 -> 005 -> 006 -> add_avg_idle
#         -> rename_userproduct (CONDICIONAL) -> seed (apenas com --seed)
#       Caminho B (sem dump ou com --no-restore):
#         create.sql -> 004 -> 005 -> 006 -> add_avg_idle
#         -> rename_userproduct (CONDICIONAL) -> seed (salvo --no-seed)
#   * Config: host/porta/dbname parseados da URL JDBC em
#     application.properties; DB_USER/DB_PASSWORD lidos do .env por parsing
#     textual (NUNCA `source`). ZERO credencial hardcoded; a senha NUNCA
#     aparece em log, stdout, stderr ou mensagem de erro.
#   * Destruir dados exige --recreate (container) e --recreate --purge-volume
#     (volume), sempre com aviso prévio. Sem essas flags NENHUMA operação
#     destrutiva (docker rm / volume rm) é executada.
#   * psql/pg_restore rodam via `docker exec` no container — não exige
#     cliente PostgreSQL instalado no host.
#   * Healthcheck aguardado com timeout (--timeout, default 120s, poll 2s);
#     timeout -> erro claro + últimas linhas de `docker logs`.
#
# ORDEM DE USO: execute ESTE script ANTES de subir o Spring.
#   O application.properties usa spring.jpa.hibernate.ddl-auto=update
#   (application.properties:12), que pode criar colunas divergentes do
#   schema canônico se o Spring subir primeiro.
#
# Uso: bash scripts/setup_postgres_docker.sh [--recreate] [--purge-volume] [--seed]
#      bash scripts/setup_postgres_docker.sh --help
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Defaults (§1.6)
# -----------------------------------------------------------------------------
CONTAINER_NAME="neondb-local"
IMAGE_NAME="postgres:18"
VOLUME_NAME="neondb_local_data"
VOLUME_EXPLICIT=false
HEALTH_TIMEOUT=120
DUMP_OVERRIDE=""

FLAG_RECREATE=false
FLAG_PURGE_VOLUME=false
FLAG_SEED=false
FLAG_NO_SEED=false
FLAG_NO_RESTORE=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_PROPS="${REPO_ROOT}/src/main/resources/application.properties"
ENV_FILE="${REPO_ROOT}/.env"
MIGRATIONS_DIR="${REPO_ROOT}/migrations"
BACKUPS_DIR="${REPO_ROOT}/backups"

# Estado derivado (preenchido durante a execução)
DB_HOST=""
DB_PORT=""
DB_NAME=""
JDBC_URL=""
DB_USER_VAL=""
DB_PASSWORD_VAL=""
ACTUAL_VOLUME=""
CONTAINER_ACTION=""
MIGRATION_PATH=""
RESTORE_STATUS=""
SEED_STATUS=""
PRESENT_TABLES=0

EXPECTED_TABLES=(
  users
  product
  registry_user_product
  product_source_observation
  energy_label_class
  energy_raw_measurement
  energy_specification
  source_metadata
  source_product
  aggregate_reference
)

# Tabelas cujo DDL NÃO está versionado no repo (não existem em create.sql nem
# nas migrations 004/005/006): elas vêm exclusivamente do dump do banco
# original (Neon). No Caminho B (banco novo sem dump) o script as reporta como
# WARN — criar o DDL delas é decisão do DEV (fora do escopo deste script).
DUMP_ONLY_TABLES=(
  energy_raw_measurement
  energy_specification
  source_metadata
  source_product
)

# -----------------------------------------------------------------------------
# Log com cores (estilo [INFO]/[OK]/[WARN]/[ERR]; cores só em TTY/NO_COLOR)
# -----------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'
  C_ERR=$'\033[1;31m'; C_RST=$'\033[0m'
else
  C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_RST=""
fi

log()  { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_RST" "$*"; }
ok()   { printf '%s[OK]%s %s\n'   "$C_OK"   "$C_RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RST" "$*" >&2; }
err()  { printf '%s[ERR]%s %s\n'  "$C_ERR"  "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  cat <<'EOF'
Uso: bash scripts/setup_postgres_docker.sh [opções]

Prepara a instância PostgreSQL local do projeto em Docker: container
saudável + schema (dump ou migrations) + dados + validação final.

IMPORTANTE: execute ANTES de subir o Spring — o application.properties usa
spring.jpa.hibernate.ddl-auto=update, que pode criar colunas divergentes do
schema canônico se o Spring subir primeiro.

Configuração lida (nunca hardcoded):
  * host/porta/dbname -> URL JDBC em src/main/resources/application.properties
  * DB_USER/DB_PASSWORD -> .env da raiz (parse textual; nunca `source`;
    a senha nunca é impressa em log, stdout ou erro)

Opções:
  --container NAME   nome do container (default: neondb-local)
  --image TAG        imagem Postgres (default: postgres:18)
  --volume NAME      volume de dados (default: neondb_local_data)
  --dump PATH        dump custom -Fc a restaurar (default: mais recente em backups/)
  --no-restore       ignora dump disponível e usa migrations + seed
  --seed             força seed também no caminho com dump
  --no-seed          pula seed no caminho sem dump
  --recreate         DESTRUTIVO (container): remove e recria o container;
                     o volume de dados é MANTIDO (exceto com --purge-volume)
  --purge-volume     DESTRUTIVO (dados): remove o volume — exige --recreate
  --timeout SECONDS  timeout do healthcheck (default: 120)
  --help             esta ajuda

Sem --recreate/--purge-volume o script nunca executa `docker rm` nem
`docker volume rm` — dados existentes são sempre preservados.

Ordem canônica (spec §1.4):
  Caminho A (dump):  pg_restore -> create.sql -> 004 -> 005 -> 006 ->
                     add_avg_idle -> rename_userproduct (só se a tabela
                     userproduct existir) -> seed (apenas com --seed)
  Caminho B (sem dump): create.sql -> 004 -> 005 -> 006 -> add_avg_idle ->
                     rename_userproduct (condicional) -> seed (salvo --no-seed)

Exemplos:
  bash scripts/setup_postgres_docker.sh
  bash scripts/setup_postgres_docker.sh --seed
  bash scripts/setup_postgres_docker.sh --recreate            # só container
  bash scripts/setup_postgres_docker.sh --recreate --purge-volume  # apaga dados
EOF
}

# -----------------------------------------------------------------------------
# Utilidades
# -----------------------------------------------------------------------------
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

in_array() {
  local needle="$1" e
  shift
  for e in "$@"; do
    [[ "$e" == "$needle" ]] && return 0
  done
  return 1
}

# Lê uma chave do .env por parsing textual — NUNCA `source` (§1.2.2).
# Formato esperado no .env: KEY=value (sem prefixo 'export ').
# Remove CR e aspas simples/duplas envolventes. Não imprime o conteúdo.
env_file_get() {
  local key="$1" line=""
  [[ -f "$ENV_FILE" ]] || return 1
  line="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -n 1 | cut -d= -f2- || true)"
  line="$(trim "${line%$'\r'}")"
  if [[ "$line" =~ ^\"(.*)\"$ ]]; then
    line="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^\'(.*)\'$ ]]; then
    line="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$line"
}

# Mascara parâmetro password= em URLs (defesa extra antes de imprimir).
mask_url() {
  printf '%s' "$1" | sed -E 's/([?&](password|pwd)=)[^&]*/\1***/Ig'
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"
}

# Preferir o volume montado em /var/lib/postgresql (o volume de dados REAL do
# Postgres); fallback: primeiro volume montado, se houver.
container_volume_of() {
  local vol=""
  vol="$(docker inspect --format \
    '{{range .Mounts}}{{if and (eq .Type "volume") (eq .Destination "/var/lib/postgresql")}}{{println .Name}}{{end}}{{end}}' \
    "$1" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$vol" ]]; then
    vol="$(docker inspect --format \
      '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
      "$1" 2>/dev/null | head -n 1 || true)"
  fi
  printf '%s' "$vol"
}

# Resolve qual volume de dados usar: o volume REAL do container (quando
# conhecido) tem prioridade sobre o default/--volume. Sem isso, --recreate
# montaria um volume vazio e orfaria o volume com os dados (perda aparente).
resolve_volume() {
  if [[ -n "$ACTUAL_VOLUME" ]]; then
    printf '%s' "$ACTUAL_VOLUME"
  else
    printf '%s' "$VOLUME_NAME"
  fi
}

# Query escalar silenciosa (sem cabeçalho). Falha => mensagem clara + exit != 0.
# stderr do psql NÃO é mergeado no valor retornado (NOTICE/WARNING poluiriam
# escalares como schema_present/contagens); stderr é capturado em tmp e só
# aparece na mensagem de falha.
q() {
  local out="" errf err
  errf="$(mktemp)" || die "falha ao criar arquivo temporário (mktemp)"
  if out="$(docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER_VAL" \
        -d "$DB_NAME" -v ON_ERROR_STOP=1 -tAq -c "$1" 2>"$errf")"; then
    rm -f "$errf"
    printf '%s' "$out"
    return 0
  fi
  err="$(cat "$errf" 2>/dev/null || true)"
  rm -f "$errf"
  die "consulta SQL falhou no container '$CONTAINER_NAME': ${err}${err:+ | }stdout: ${out}"
}

# Query com saída formatada (tabela) para o relatório.
show_sql() {
  local out=""
  if ! out="$(docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER_VAL" \
        -d "$DB_NAME" -v ON_ERROR_STOP=1 -X -c "$1" 2>&1)"; then
    die "consulta SQL falhou no container '$CONTAINER_NAME': $out"
  fi
  printf '%s\n' "$out"
}

# Aplica um arquivo .sql via stdin no psql do container (ON_ERROR_STOP=1).
apply_sql() {
  local file="$1" out=""
  [[ -f "$file" ]] || die "arquivo SQL não encontrado: $file"
  log "Aplicando ${file#"${REPO_ROOT}"/} ..."
  if ! out="$(docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER_VAL" \
        -d "$DB_NAME" -v ON_ERROR_STOP=1 -q < "$file" 2>&1)"; then
    die "falha ao aplicar ${file#"${REPO_ROOT}"/}: ${out}"
  fi
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}

# -----------------------------------------------------------------------------
# Argumentos (§1.6)
# -----------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --container)
        [[ $# -ge 2 ]] || die "--container requer um valor"
        CONTAINER_NAME="$2"; shift 2 ;;
      --image)
        [[ $# -ge 2 ]] || die "--image requer um valor"
        IMAGE_NAME="$2"; shift 2 ;;
      --volume)
        [[ $# -ge 2 ]] || die "--volume requer um valor"
        VOLUME_NAME="$2"; VOLUME_EXPLICIT=true; shift 2 ;;
      --dump)
        [[ $# -ge 2 ]] || die "--dump requer um valor"
        DUMP_OVERRIDE="$2"; shift 2 ;;
      --no-restore) FLAG_NO_RESTORE=true; shift ;;
      --seed)       FLAG_SEED=true; shift ;;
      --no-seed)    FLAG_NO_SEED=true; shift ;;
      --recreate)   FLAG_RECREATE=true; shift ;;
      --purge-volume) FLAG_PURGE_VOLUME=true; shift ;;
      --timeout)
        [[ $# -ge 2 ]] || die "--timeout requer um valor em segundos"
        HEALTH_TIMEOUT="$2"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) die "opção desconhecida: $1 (use --help)" ;;
    esac
  done

  [[ "$HEALTH_TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout deve ser um inteiro (recebido: $HEALTH_TIMEOUT)"
  if $FLAG_PURGE_VOLUME && ! $FLAG_RECREATE; then
    die "--purge-volume exige --recreate junto (remover volume sem recriar o container não é um caminho suportado)"
  fi
  if $FLAG_SEED && $FLAG_NO_SEED; then
    die "--seed e --no-seed são mutuamente exclusivos"
  fi
}

# -----------------------------------------------------------------------------
# Config: URL JDBC (application.properties) + credenciais (.env) — §1.2
# -----------------------------------------------------------------------------
read_config() {
  [[ -f "$APP_PROPS" ]] || die "application.properties não encontrado: $APP_PROPS"

  local raw=""
  raw="$(grep -E '^spring\.datasource\.url=' "$APP_PROPS" 2>/dev/null | head -n 1 | cut -d= -f2- || true)"
  raw="$(trim "${raw%$'\r'}")"
  [[ -n "$raw" ]] || die "spring.datasource.url não encontrada em $APP_PROPS"

  if [[ "$raw" =~ ^jdbc:postgresql://([^:/?]+):([0-9]+)/([^?]+)(\?.*)?$ ]]; then
    JDBC_URL="$raw"
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    DB_NAME="${BASH_REMATCH[3]}"
  else
    die "URL JDBC não parseável em application.properties: $(mask_url "$raw") (formato esperado: jdbc:postgresql://HOST:PORT/DBNAME) — host/porta/dbname não serão adivinhados"
  fi
  [[ -n "$DB_NAME" ]] || die "dbname vazio na URL JDBC: $(mask_url "$raw")"

  if [[ "$DB_HOST" != "localhost" && "$DB_HOST" != "127.0.0.1" ]]; then
    warn "host da URL JDBC é '$DB_HOST' (não localhost): a instância Docker só atende conexões mapeadas localmente — seguindo assim mesmo"
  fi

  # Credenciais: variável de ambiente > .env > erro (sem flags de senha na CLI,
  # que apareceriam em `ps`). NUNCA `source` do .env; nunca imprimir valores.
  DB_USER_VAL="${DB_USER:-}"
  [[ -n "$DB_USER_VAL" ]] || DB_USER_VAL="$(env_file_get DB_USER || true)"
  [[ -n "$DB_USER_VAL" ]] || die "DB_USER não definida: exporte DB_USER ou adicione a linha 'DB_USER=<valor>' ao .env (${ENV_FILE}) — formato KEY=value, sem prefixo 'export '"

  DB_PASSWORD_VAL="${DB_PASSWORD:-}"
  [[ -n "$DB_PASSWORD_VAL" ]] || DB_PASSWORD_VAL="$(env_file_get DB_PASSWORD || true)"
  [[ -n "$DB_PASSWORD_VAL" ]] || die "DB_PASSWORD não definida: exporte DB_PASSWORD ou adicione a linha 'DB_PASSWORD=<valor>' ao .env (${ENV_FILE}) — formato KEY=value, sem prefixo 'export '"

  log "Config: container=${CONTAINER_NAME} imagem=${IMAGE_NAME} db=${DB_NAME} host=${DB_HOST}:${DB_PORT} user=${DB_USER_VAL}"
}

# -----------------------------------------------------------------------------
# Docker / ciclo de vida — §1.3
# -----------------------------------------------------------------------------
check_docker() {
  command -v docker >/dev/null 2>&1 || die "docker não encontrado no PATH"
  docker info >/dev/null 2>&1 || die "daemon Docker inacessível (docker info falhou)"
}

create_container() {
  local busy=""
  busy="$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E ":${DB_PORT}->" || true)"
  if [[ -n "$busy" ]]; then
    die "porta ${DB_PORT} já está publicada por outro container: ${busy} — nada foi removido (sem --force). Pare o conflito manualmente e reexecute."
  fi

  # Prioridade: volume real do container removido (ACTUAL_VOLUME, quando
  # conhecido) > default/--volume. Caso contrário --recreate montaria um
  # volume vazio e orfaria o volume com os dados (contrato: volume MANTIDO).
  local target_volume=""
  target_volume="$(resolve_volume)"

  log "Criando container '${CONTAINER_NAME}' (${IMAGE_NAME}), volume '${target_volume}', porta ${DB_PORT}->5432 ..."
  local out=""
  if ! out="$(docker run -d \
      --name "$CONTAINER_NAME" \
      -e POSTGRES_DB="$DB_NAME" \
      -e POSTGRES_USER="$DB_USER_VAL" \
      -e POSTGRES_PASSWORD="$DB_PASSWORD_VAL" \
      -e "POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C" \
      -p "${DB_PORT}:5432" \
      --health-cmd "pg_isready -U ${DB_USER_VAL} -d ${DB_NAME}" \
      --health-interval 10s \
      --health-timeout 5s \
      --health-retries 5 \
      --health-start-period 5s \
      -v "${target_volume}:/var/lib/postgresql" \
      "$IMAGE_NAME" 2>&1)"; then
    die "docker run falhou: ${out}"
  fi
  CONTAINER_ACTION="criado"
  ACTUAL_VOLUME="$target_volume"
  ok "container criado (id ${out:0:12})"
}

check_coherence() {
  local envs pg_user pg_db pg_pw
  envs="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  pg_user="$(printf '%s\n' "$envs" | sed -n 's/^POSTGRES_USER=//p' | head -n 1)"
  pg_db="$(printf '%s\n' "$envs" | sed -n 's/^POSTGRES_DB=//p' | head -n 1)"
  pg_pw="$(printf '%s\n' "$envs" | sed -n 's/^POSTGRES_PASSWORD=//p' | head -n 1)"

  if [[ -n "$pg_user" && "$pg_user" != "$DB_USER_VAL" ]]; then
    die "container '$CONTAINER_NAME' tem POSTGRES_USER='${pg_user}', mas DB_USER do .env é '${DB_USER_VAL}' — não dá para alinhar sem recriar (use --recreate se quiser recomeçar)"
  fi
  if [[ -n "$pg_db" && "$pg_db" != "$DB_NAME" ]]; then
    die "container '$CONTAINER_NAME' tem POSTGRES_DB='${pg_db}', mas a URL JDBC aponta para '${DB_NAME}' — não dá para alinhar sem recriar (use --recreate se quiser recomeçar)"
  fi
  if [[ -n "$pg_pw" && "$pg_pw" != "$DB_PASSWORD_VAL" ]]; then
    warn "POSTGRES_PASSWORD do container diverge de DB_PASSWORD (.env). Correção sugerida (NÃO executada pelo script, senha não exibida):"
    warn "  ALTER USER ${DB_USER_VAL} WITH PASSWORD '<senha-do-.env>';"
  fi
}

handle_lifecycle() {
  if $FLAG_RECREATE; then
    ACTUAL_VOLUME="$(container_volume_of "$CONTAINER_NAME")"
    if container_exists; then
      warn "--recreate: o container '${CONTAINER_NAME}' será REMOVIDO e recriado."
      if ! $FLAG_PURGE_VOLUME; then
        warn "O volume de dados será MANTIDO (${ACTUAL_VOLUME:-$VOLUME_NAME})."
      fi
      log "Removendo container '${CONTAINER_NAME}' (--recreate) ..."
      docker rm -f "$CONTAINER_NAME" >/dev/null \
        || die "falha ao remover container '${CONTAINER_NAME}'"
    else
      log "--recreate: container '${CONTAINER_NAME}' não existe — nada a remover."
    fi
    if $FLAG_PURGE_VOLUME; then
      # Mesma resolução de create_container: volume REAL do container removido
      # (quando conhecido) tem prioridade sobre o default/--volume — purgar o
      # volume errado orfaria os dados e montaria outro volume vazio.
      local target_vol=""
      target_vol="$(resolve_volume)"
      if $VOLUME_EXPLICIT && [[ "$target_vol" != "$VOLUME_NAME" ]]; then
        warn "--volume ${VOLUME_NAME} difere do volume real do container removido (${target_vol}) — purgando o volume real (${target_vol}) para ser coerente com o volume que será montado na recriação."
      fi
      warn "--purge-volume: o volume '${target_vol}' será REMOVIDO — TODOS OS DADOS NELE SERÃO PERDIDOS."
      if docker volume inspect "$target_vol" >/dev/null 2>&1; then
        docker volume rm -f "$target_vol" >/dev/null \
          || die "falha ao remover volume '${target_vol}'"
        ok "volume '${target_vol}' removido"
      else
        log "volume '${target_vol}' não existe — nada a remover."
      fi
    fi
  fi

  if container_exists; then
    CONTAINER_ACTION="reutilizado"
    ACTUAL_VOLUME="$(container_volume_of "$CONTAINER_NAME")"
    [[ -n "$ACTUAL_VOLUME" ]] || ACTUAL_VOLUME="$VOLUME_NAME"
    if $VOLUME_EXPLICIT && [[ "$VOLUME_NAME" != "$ACTUAL_VOLUME" ]]; then
      warn "--volume ${VOLUME_NAME} difere do volume real do container (${ACTUAL_VOLUME}); seguindo com o volume real para não tocar nos dados"
    fi
    log "Container '${CONTAINER_NAME}' já existe — reutilizando (nada será recriado)."
    check_coherence

    local running=""
    running="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo false)"
    if [[ "$running" != "true" ]]; then
      log "Container parado — iniciando com 'docker start' (dados preservados) ..."
      docker start "$CONTAINER_NAME" >/dev/null || die "docker start falhou no container '${CONTAINER_NAME}'"
    fi

    local mapped=""
    mapped="$(docker port "$CONTAINER_NAME" 5432/tcp 2>/dev/null | head -n 1 | awk -F: '{print $NF}' || true)"
    if [[ -z "$mapped" ]]; then
      warn "container '${CONTAINER_NAME}' não publica a porta 5432/tcp — conexões pela URL JDBC (${DB_HOST}:${DB_PORT}) podem falhar"
    elif [[ "$mapped" != "$DB_PORT" ]]; then
      die "container publica a porta ${mapped}, mas a URL JDBC usa ${DB_PORT} — a aplicação Spring não conseguiria conectar. Ajuste application.properties ou recrie o container com a porta correta (nada foi alterado neste container)."
    fi
  else
    if $VOLUME_EXPLICIT && docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
      log "Volume '${VOLUME_NAME}' já existe — será reutilizado."
    fi
    create_container
  fi
}

# Aguarda 'healthy' com timeout (§1.5.1). Timeout/falha => docker logs.
# Container SEM healthcheck (reusado, criado fora do script): cai para
# polling de `docker exec pg_isready` em vez de esperar 'unknown' até o timeout.
wait_healthy() {
  local waited=0 status running
  log "Aguardando healthcheck 'healthy' (timeout ${HEALTH_TIMEOUT}s, polling 2s) ..."
  status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
  if [[ "$status" == "none" ]]; then
    log "container '${CONTAINER_NAME}' não tem healthcheck configurado — usando polling de 'pg_isready' como sinal de prontidão."
    while true; do
      if docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER_VAL" -d "$DB_NAME" >/dev/null 2>&1; then
        ok "container '${CONTAINER_NAME}' aceitando conexões (pg_isready OK, sem healthcheck; após ${waited}s)"
        return 0
      fi
      running="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo false)"
      if [[ "$running" != "true" ]]; then
        err "container '${CONTAINER_NAME}' não está em execução — últimas 30 linhas de 'docker logs':"
        docker logs --tail 30 "$CONTAINER_NAME" >&2 || true
        exit 1
      fi
      if (( waited >= HEALTH_TIMEOUT )); then
        err "timeout de ${HEALTH_TIMEOUT}s aguardando 'pg_isready' (container sem healthcheck) — últimas 30 linhas de 'docker logs':"
        docker logs --tail 30 "$CONTAINER_NAME" >&2 || true
        exit 1
      fi
      sleep 2
      waited=$((waited + 2))
    done
  fi
  while true; do
    status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
    if [[ "$status" == "healthy" ]]; then
      ok "container '${CONTAINER_NAME}' healthy (após ${waited}s)"
      return 0
    fi
    running="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo false)"
    if [[ "$running" != "true" ]]; then
      err "container '${CONTAINER_NAME}' não está em execução (health: ${status}) — últimas 30 linhas de 'docker logs':"
      docker logs --tail 30 "$CONTAINER_NAME" >&2 || true
      exit 1
    fi
    if (( waited >= HEALTH_TIMEOUT )); then
      err "timeout de ${HEALTH_TIMEOUT}s aguardando 'healthy' (health atual: ${status}) — últimas 30 linhas de 'docker logs':"
      docker logs --tail 30 "$CONTAINER_NAME" >&2 || true
      exit 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

# -----------------------------------------------------------------------------
# Dump — §1.4
# -----------------------------------------------------------------------------
select_dump() {
  if [[ -n "$DUMP_OVERRIDE" ]]; then
    [[ -f "$DUMP_OVERRIDE" ]] || die "--dump: arquivo não encontrado: $DUMP_OVERRIDE"
    printf '%s' "$DUMP_OVERRIDE"
    return 0
  fi
  [[ -d "$BACKUPS_DIR" ]] || return 0
  ls -t "$BACKUPS_DIR"/*.dump 2>/dev/null | head -n 1 || true
}

run_restore() {
  local dump="$1" out=""
  log "Restaurando dump via docker exec pg_restore (--no-owner --no-privileges --exit-on-error): ${dump#"${REPO_ROOT}"/}"
  if ! out="$(docker exec -i "$CONTAINER_NAME" pg_restore -U "$DB_USER_VAL" \
        -d "$DB_NAME" --no-owner --no-privileges --exit-on-error \
        < "$dump" 2>&1)"; then
    die "pg_restore falhou em ${dump}: ${out}"
  fi
  [[ -n "$out" ]] && printf '%s\n' "$out"
  ok "dump restaurado"
  return 0
}

# Guard de idempotência do Caminho A: pula o pg_restore APENAS se a tabela
# users existe E contém dados. Um pg_restore anterior que falhou no meio pode
# ter criado a tabela sem populá-la — nesse caso o restore roda de novo em
# vez de deixar um schema parcial "congelado" para sempre. (Duas queries, não
# uma com AND: o planner resolveria a relação 'users' mesmo se o to_regclass
# fosse falso, e falharia com "relation does not exist".)
schema_present() {
  local exists="" cnt=""
  exists="$(q "SELECT to_regclass('public.users') IS NOT NULL")" \
    || die "não foi possível consultar o banco (container saudável?)"
  [[ "$exists" == "t" ]] || return 1
  cnt="$(q "SELECT COUNT(*) FROM users")" \
    || die "não foi possível contar a tabela 'users' (container saudável?)"
  [[ "$cnt" =~ ^[0-9]+$ ]] || die "contagem inesperada de users: '${cnt}'"
  (( cnt > 0 ))
}

# -----------------------------------------------------------------------------
# Migrações — ordem canônica §1.4
# -----------------------------------------------------------------------------
apply_rename_conditional() {
  local v=""
  v="$(q "SELECT to_regclass('public.userproduct') IS NOT NULL AND to_regclass('public.registry_user_product') IS NULL")"
  if [[ "$v" == "t" ]]; then
    log "Tabela legada 'userproduct' encontrada (e 'registry_user_product' ainda não existe) — aplicando rename."
    apply_sql "${MIGRATIONS_DIR}/rename_userproduct_to_registry_user_product.sql"
  else
    log "rename_userproduct: rename não aplicável ('userproduct' ausente, ou 'registry_user_product' já existe — ex.: dump legado + create.sql) — pulado."
  fi
}

apply_migrations_tail() {
  apply_sql "${MIGRATIONS_DIR}/create.sql"
  apply_sql "${MIGRATIONS_DIR}/004_canonical_product_observations.sql"
  apply_sql "${MIGRATIONS_DIR}/005_canonical_product_contract.sql"
  apply_sql "${MIGRATIONS_DIR}/006_collector_ingestion_tables.sql"
  apply_sql "${MIGRATIONS_DIR}/add_avg_idle_energy_for_hour.sql"
  apply_rename_conditional
}

apply_schema_and_data() {
  MIGRATION_PATH="B"
  RESTORE_STATUS="não aplicado (sem dump ou com --no-restore)"
  SEED_STATUS="não aplicado"

  local dump=""
  dump="$(select_dump)"

  if $FLAG_NO_RESTORE; then
    log "--no-restore: dump ignorado; usando migrations + seed (Caminho B)."
    MIGRATION_PATH="B"
  elif [[ -z "$dump" ]]; then
    log "Nenhum dump encontrado em backups/*.dump — usando migrations + seed (Caminho B)."
    MIGRATION_PATH="B"
  else
    MIGRATION_PATH="A"
    if schema_present; then
      RESTORE_STATUS="pulado — schema já inicializado com dados (idempotência: dados existentes preservados)"
      log "Dump disponível (${dump#"${REPO_ROOT}"/}) mas a tabela 'users' já existe com dados: pg_restore PULADO nesta reexecução para preservar os dados."
      log "Para recomeçar do dump, use --recreate (mantém volume) + apague o volume só com --purge-volume."
    else
      run_restore "$dump"
      RESTORE_STATUS="restaurado: ${dump#"${REPO_ROOT}"/}"
    fi
  fi

  apply_migrations_tail

  if [[ "$MIGRATION_PATH" == "B" ]]; then
    if $FLAG_NO_SEED; then
      SEED_STATUS="pulado (--no-seed)"
      log "--no-seed: seed ignorado."
    else
      apply_sql "${MIGRATIONS_DIR}/seed.sql"
      SEED_STATUS="aplicado: migrations/seed.sql"
    fi
  else
    if $FLAG_SEED; then
      apply_sql "${MIGRATIONS_DIR}/seed.sql"
      SEED_STATUS="aplicado: migrations/seed.sql (--seed)"
    else
      SEED_STATUS="pulado (Caminho A — dados vieram do dump; use --seed para forçar)"
      log "Caminho A: seed não aplicado por padrão ($SEED_STATUS)."
    fi
  fi
}

# -----------------------------------------------------------------------------
# Validação final — §1.5.2/§1.5.3
# -----------------------------------------------------------------------------
validate_database() {
  log "Validação final: 10 tabelas, contagens, limiares e integridade referencial ..."

  # 1) Tabelas esperadas
  local values="" sep="" t missing=""
  for t in "${EXPECTED_TABLES[@]}"; do
    values+="${sep}('${t}')"
    sep=", "
  done
  missing="$(q "SELECT COALESCE(string_agg(x, ',' ORDER BY x), '') FROM (VALUES ${values}) v(x) WHERE to_regclass('public.' || x) IS NULL")"

  local -a missing_arr=()
  [[ -n "$missing" ]] && IFS=',' read -r -a missing_arr <<< "$missing"

  # No Caminho A (dump/restauração) as 10 tabelas são obrigatórias. No
  # Caminho B, as tabelas sem DDL versionado no repo (DUMP_ONLY_TABLES) só
  # existem via dump: ausência delas é WARN + reporte, nunca improviso de DDL.
  local -a fatal=()
  for t in "${missing_arr[@]}"; do
    if [[ "$MIGRATION_PATH" == "A" ]] || ! in_array "$t" "${DUMP_ONLY_TABLES[@]}"; then
      fatal+=("$t")
    fi
  done
  if (( ${#fatal[@]} > 0 )); then
    local fatal_str=""
    fatal_str="$(IFS=,; echo "${fatal[*]}")"
    if [[ "$MIGRATION_PATH" == "A" && "$RESTORE_STATUS" == pulado* ]]; then
      die "tabelas ausentes no schema: ${fatal_str} — o dump estava disponível, mas a restauração foi PULADA por schema parcial (execução anterior falhou no meio). Recomece com: bash scripts/setup_postgres_docker.sh --recreate --purge-volume (DESTRUTIVO: apaga o volume de dados)"
    fi
    die "tabelas ausentes no schema: ${fatal_str}"
  fi
  for t in "${missing_arr[@]}"; do
    warn "tabela '${t}' ausente: DDL não versionado no repo (existe apenas no dump/BD original) — o Caminho B não a cria; restaure um dump ou peça a migration dessas tabelas ao DEV"
  done

  local present_count=$(( ${#EXPECTED_TABLES[@]} - ${#missing_arr[@]} ))
  PRESENT_TABLES="$present_count"
  ok "${present_count}/${#EXPECTED_TABLES[@]} tabelas presentes"

  # 2) Contagens (reportadas) — apenas das tabelas existentes
  local counts_sql="" csep=""
  for t in "${EXPECTED_TABLES[@]}"; do
    if in_array "$t" "${missing_arr[@]}"; then
      continue
    fi
    counts_sql+="${csep}SELECT '${t}' AS tabela, COUNT(*) AS linhas FROM ${t}"
    csep=" UNION ALL "
  done
  show_sql "${counts_sql} ORDER BY tabela;"

  local users_count product_count
  users_count="$(q "SELECT COUNT(*) FROM users")"
  product_count="$(q "SELECT COUNT(*) FROM product")"

  # 3) Limiares por caminho (§1.5.2)
  if [[ "$MIGRATION_PATH" == "A" ]]; then
    if (( users_count < 1 )); then
      if [[ "$RESTORE_STATUS" == pulado* ]]; then
        die "limiar Caminho A violado: users >= 1 (obtido: ${users_count}) — o dump está disponível, mas a restauração foi PULADA por schema parcial (tabela users existe de uma execução anterior que falhou no meio). Recomece com: bash scripts/setup_postgres_docker.sh --recreate --purge-volume (DESTRUTIVO: apaga o volume de dados)"
      fi
      die "limiar Caminho A violado: users >= 1 (obtido: ${users_count})"
    fi
    if (( product_count < 1 )); then
      if [[ "$RESTORE_STATUS" == pulado* ]]; then
        die "limiar Caminho A violado: product >= 1 (obtido: ${product_count}) — o dump está disponível, mas a restauração foi PULADA por schema parcial (tabela users já existia de uma execução anterior que falhou no meio). Recomece com: bash scripts/setup_postgres_docker.sh --recreate --purge-volume (DESTRUTIVO: apaga o volume de dados)"
      fi
      die "limiar Caminho A violado: product >= 1 (obtido: ${product_count})"
    fi
    ok "limiares Caminho A: users=${users_count} (>=1), product=${product_count} (>=1)"
  else
    (( users_count >= 1 )) || die "limiar Caminho B violado (seed): users >= 1 (obtido: ${users_count})"
    log "limiar Caminho B: users=${users_count} (>=1); product=${product_count} (reportado, sem exigência — popula via coletor/dump)"
  fi

  # 4) Integridade referencial (espelha migrate.sh:189-194 + órfãos)
  show_sql "
SELECT
  (SELECT COUNT(*) FROM registry_user_product r JOIN users u ON u.id = r.user_id)       AS rup_fk_users_ok,
  (SELECT COUNT(*) FROM registry_user_product r JOIN product p ON p.id = r.product_id)   AS rup_fk_product_ok,
  (SELECT COUNT(*) FROM product_source_observation o JOIN product p ON p.id = o.canonical_product_id) AS pso_fk_product_ok,
  (SELECT COUNT(*) FROM registry_user_product)       AS rup_total,
  (SELECT COUNT(*) FROM product_source_observation)  AS pso_total;"

  local orphans
  orphans="$(q "
SELECT
      (SELECT COUNT(*) FROM registry_user_product r
        WHERE r.user_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = r.user_id))
    + (SELECT COUNT(*) FROM registry_user_product r
        WHERE r.product_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM product p WHERE p.id = r.product_id))
    + (SELECT COUNT(*) FROM product_source_observation o
        WHERE o.canonical_product_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM product p WHERE p.id = o.canonical_product_id));")"
  if (( orphans > 0 )); then
    die "integridade referencial violada: ${orphans} registro(s) órfão(s) (registry_user_product->users/product, product_source_observation->product)"
  fi
  ok "FKs checadas: 0 registro(s) órfão(s)"
  ok "validação final verde"
}

# -----------------------------------------------------------------------------
# Probe TCP host-side — "pronto" só se a porta da URL JDBC aceitar conexão
# -----------------------------------------------------------------------------
# Confirma a partir do HOST (não do container) que ${DB_HOST}:${DB_PORT} aceita
# conexão TCP. Sem isso, um container reutilizado com porta divergente só
# gerava WARN e o script terminava 0 dizendo "pronto", embora o Spring nunca
# conseguisse conectar.
probe_tcp_connectivity() {
  log "Probe TCP host-side: testando ${DB_HOST}:${DB_PORT} ..."
  if timeout 2 bash -c "</dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
    ok "porta ${DB_HOST}:${DB_PORT} aceita conexão TCP a partir do host"
  else
    die "a porta ${DB_HOST}:${DB_PORT} NÃO aceita conexão TCP a partir do host — a aplicação não conseguiria conectar apesar do banco interno estar no ar. Verifique o mapeamento de porta do container '${CONTAINER_NAME}' (docker port ${CONTAINER_NAME}) e a URL JDBC no application.properties"
  fi
}

# -----------------------------------------------------------------------------
# Relatório final — §1.5.3 (senha sempre mascarada)
# -----------------------------------------------------------------------------
final_report() {
  local masked_jdbc masked_psql
  masked_jdbc="$(mask_url "$JDBC_URL")"
  masked_psql="postgresql://${DB_USER_VAL}:***@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=disable"

  printf '\n'
  ok "Instância PostgreSQL pronta"
  printf '  Container : %s (%s) — %s\n' "$CONTAINER_NAME" "$IMAGE_NAME" "$CONTAINER_ACTION"
  printf '  Volume    : %s\n' "$ACTUAL_VOLUME"
  printf '  Caminho   : %s\n' "$MIGRATION_PATH"
  printf '  Restore   : %s\n' "$RESTORE_STATUS"
  printf '  Seed      : %s\n' "$SEED_STATUS"
  printf '  Tabelas   : %s/%s presentes, contagens reportadas acima, FKs checadas\n' "$PRESENT_TABLES" "${#EXPECTED_TABLES[@]}"
  printf '  Conexão   : %s\n' "$masked_psql"
  printf '  JDBC      : %s\n' "$masked_jdbc"
  printf '  Próximo   : suba o Spring somente AGORA (ddl-auto=update diverge se subir antes)\n'
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  parse_args "$@"
  read_config
  check_docker
  handle_lifecycle
  wait_healthy
  apply_schema_and_data
  validate_database
  probe_tcp_connectivity
  final_report
}

main "$@"
