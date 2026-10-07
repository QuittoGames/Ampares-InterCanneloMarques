#!/usr/bin/env bash
# ============================================================================
# NEON TO LOCAL POSTGRESQL MIGRATION - STANDALONE FEDORA SSH REPOSITORY
#
# O servidor SSH é usado como fonte dos arquivos de migração.
#
# Execução:
#   bash migrate_remote.sh
#
# Opcionalmente:
#   REPO_SSH="quitto@QUITTO-COFFEE-SERVER" \
#   REPO_PATH="/home/quitto/migration" \
#   bash migrate_remote.sh
#
# Requisitos:
#   - SSH funcionando para o servidor
#   - SCP disponível
#   - chave SSH/configuração de autenticação já configurada
# ============================================================================

set -euo pipefail

REPO_SSH="${REPO_SSH:-quitto@QUITTO-COFFEE-SERVER}"
REPO_PATH="${REPO_PATH:-/home/quitto/migration}"
MIGRATION_DIR="${MIGRATION_DIR:-$HOME/migration}"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

# ============================================================================
# Verificações
# ============================================================================

check_fedora() {
    if [[ ! -r /etc/os-release ]]; then
        err "Não foi possível identificar a distribuição do sistema"
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "fedora" ]]; then
        err "Este instalador requer Fedora (detectado: ${PRETTY_NAME:-desconhecida})"
    fi

    if ! command -v dnf &>/dev/null; then
        err "dnf não encontrado; não é possível instalar dependências no Fedora"
    fi

    ok "Fedora OK"
}

check_ssh_repo() {
    if ! command -v ssh &>/dev/null; then
        err "SSH não encontrado"
    fi

    if ! command -v scp &>/dev/null; then
        err "SCP não encontrado"
    fi

    log "Testando acesso SSH ao repositório remoto..."

    if ! ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=8 \
        "$REPO_SSH" \
        "test -d '$REPO_PATH'" \
        &>/dev/null
    then
        err "Não foi possível acessar o repositório SSH: ${REPO_SSH}:${REPO_PATH}"
    fi

    ok "Repositório SSH acessível"
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        err "Docker não instalado"
    fi

    if ! docker compose version &>/dev/null; then
        err "Docker Compose plugin não instalado"
    fi

    if ! docker ps &>/dev/null; then
        err "Sem acesso ao Docker socket. Use: sudo usermod -aG docker \$USER && newgrp docker"
    fi

    ok "Docker OK"
}

check_psql() {
    if command -v psql &>/dev/null && command -v pg_dump &>/dev/null; then
        ok "Cliente PostgreSQL OK"
        return
    fi

    if ! command -v sudo &>/dev/null && [[ "${EUID}" -ne 0 ]]; then
        err "sudo não encontrado; execute como root ou instale sudo para instalar o cliente PostgreSQL"
    fi

    log "Instalando cliente PostgreSQL via dnf..."

    if [[ "${EUID}" -eq 0 ]]; then
        dnf install -y postgresql >/dev/null
    else
        sudo dnf install -y postgresql >/dev/null
    fi

    if ! command -v psql &>/dev/null || ! command -v pg_dump &>/dev/null; then
        err "O pacote postgresql foi instalado, mas psql/pg_dump não estão disponíveis"
    fi

    ok "Cliente PostgreSQL OK"
}

# ============================================================================
# Download via SSH
# ============================================================================

download_file() {
    local file="$1"

    log "Obtendo ${file} via SSH..."

    if ! scp \
        -q \
        -o BatchMode=yes \
        -o ConnectTimeout=8 \
        "${REPO_SSH}:${REPO_PATH}/${file}" \
        "${MIGRATION_DIR}/${file}"
    then
        return 1
    fi

    return 0
}
download_files() {
    log "Sincronizando arquivos de ${REPO_SSH}:${REPO_PATH}..."

    mkdir -p "$MIGRATION_DIR"
    cd "$MIGRATION_DIR"

    local files=(
        "neon_to_local.sql"
        "neon_data.sql"
        "docker-compose.yml"
        "README.md"
        "neon_inventory.md"
    )

    for f in "${files[@]}"; do
        log "Baixando $f..."

        if ! scp \
            -q \
            -o BatchMode=yes \
            -o ConnectTimeout=8 \
            "${REPO_SSH}:${REPO_PATH}/${f}" \
            "$f"
        then
            err "Falha ao obter ${f} de ${REPO_SSH}:${REPO_PATH}"
        fi
    done

    # .env.example é opcional
    if ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=8 \
        "$REPO_SSH" \
        "test -f '${REPO_PATH}/.env.example'"
    then
        scp \
            -q \
            -o BatchMode=yes \
            "${REPO_SSH}:${REPO_PATH}/.env.example" \
            .env.example
    fi

    # Nunca sobrescrever .env existente automaticamente.
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            chmod 600 .env
        else
            err ".env não existe e .env.example não foi encontrado"
        fi
    fi

    chmod 600 .env

    ok "Arquivos sincronizados em $MIGRATION_DIR"
}

# ============================================================================
# Pipeline de migração
# ============================================================================

run_migration() {
    cd "$MIGRATION_DIR"

    log "1/6 Subindo PostgreSQL 18..."

    docker compose down -v 2>/dev/null || true
    docker compose up -d

    log "2/6 Aguardando healthcheck..."

    local tries=30

    while (( tries-- > 0 )); do
        if docker compose ps --format json 2>/dev/null \
            | grep -q '"Health":"healthy"'
        then
            break
        fi

        sleep 2
    done

    if (( tries <= 0 )); then
        err "PostgreSQL não ficou saudável"
    fi

    ok "PostgreSQL saudável"

    log "3/6 Aplicando schema..."

    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql \
        -h localhost \
        -p 5432 \
        -U neondb_owner \
        -d neondb \
        -v ON_ERROR_STOP=1 \
        < neon_to_local.sql

    ok "Schema aplicado"

    log "4/6 Carregando dados..."

    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql \
        -h localhost \
        -p 5432 \
        -U neondb_owner \
        -d neondb \
        < neon_data.sql \
        2>&1 \
        | grep -v "^SET\|^ set_config" || true

    ok "Dados carregados"

    log "5/6 Corrigindo tabela 'users' (dados reais do Neon)..."

    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql \
        -h localhost \
        -p 5432 \
        -U neondb_owner \
        -d neondb \
        -c "TRUNCATE users RESTART IDENTITY CASCADE;"

    PGPASSWORD=npg_sty2oZOQxR7U \
    pg_dump \
        -h ep-snowy-mouse-awycvg31-pooler.c-12.us-east-1.aws.neon.tech \
        -p 5432 \
        -U neondb_owner \
        -d neondb \
        --data-only \
        --table=users \
        --no-owner \
        --no-privileges \
    | PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
      psql \
        -h localhost \
        -p 5432 \
        -U neondb_owner \
        -d neondb

    PGPASSWORD=npg_sty2oZOQxR7U \
    pg_dump \
        -h ep-snowy-mouse-awycvg31-pooler.c-12.us-east-1.aws.neon.tech \
        -p 5432 \
        -U neondb_owner \
        -d neondb \
        --data-only \
        --table=registry_user_product \
        --no-owner \
        --no-privileges \
    | PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
      psql \
        -h localhost \
        -p 5432 \
        -U neondb_owner \
        -d neondb

    ok "Tabela users corrigida"

    log "6/6 Validando..."

    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql \
        -h localhost \
        -p 5432 \
        -U neondb_owner \
        -d neondb \
        -c "
            SELECT 'users' t, COUNT(*) c FROM users
            UNION ALL SELECT 'product', COUNT(*) FROM product
            UNION ALL SELECT 'product_source_observation', COUNT(*) FROM product_source_observation
            UNION ALL SELECT 'registry_user_product', COUNT(*) FROM registry_user_product
            UNION ALL SELECT 'energy_label_class', COUNT(*) FROM energy_label_class
            UNION ALL SELECT 'energy_raw_measurement', COUNT(*) FROM energy_raw_measurement
            UNION ALL SELECT 'energy_specification', COUNT(*) FROM energy_specification
            UNION ALL SELECT 'source_metadata', COUNT(*) FROM source_metadata
            UNION ALL SELECT 'source_product', COUNT(*) FROM source_product
            UNION ALL SELECT 'aggregate_reference', COUNT(*) FROM aggregate_reference;
        "

    ok "Validação OK"
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo "============================================================================"
    echo "  NEON → LOCAL POSTGRESQL MIGRATION (SSH REPOSITORY)"
    echo "============================================================================"
    echo ""
    echo "Repositório:"
    echo "  SSH:  $REPO_SSH"
    echo "  PATH: $REPO_PATH"
    echo ""

    check_fedora
    check_ssh_repo
    check_docker
    check_psql
    download_files
    run_migration

    echo ""
    echo "============================================================================"
    ok "MIGRAÇÃO CONCLUÍDA"
    echo "============================================================================"
    echo ""
    echo "Conexão:"
    echo "  postgresql://neondb_owner:***@localhost:5432/neondb"
    echo ""
    echo "Arquivos em:"
    echo "  $MIGRATION_DIR"
    echo ""
    echo "Para gerenciar:"
    echo "  cd $MIGRATION_DIR"
    echo "  docker compose [up|down|logs|ps]"
}

main "$@"
