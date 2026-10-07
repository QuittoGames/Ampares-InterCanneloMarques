#!/usr/bin/env bash
# ============================================================================
# NEON TO LOCAL POSTGRESQL MIGRATION SCRIPT
# Usage: curl -sSL https://raw.githubusercontent.com/<user>/<repo>/main/migrate.sh | bash
#        ou: bash migrate.sh
# ============================================================================

set -euo pipefail

# --- Configuração ---
MIGRATION_DIR="/home/quitto/migration"
REPO_URL="https://github.com/QuittoGames/coffe_server"  # ajuste se necessário
BRANCH="main"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*"; }

# --- Verificações iniciais ---
check_docker() {
    if ! command -v docker &> /dev/null; then
        err "Docker não encontrado. Instale: https://docs.docker.com/engine/install/"
        exit 1
    fi
    if ! docker compose version &> /dev/null; then
        err "Docker Compose não encontrado (plugin 'compose')."
        exit 1
    fi
    if ! docker ps &> /dev/null; then
        err "Sem permissão para Docker socket. Rode com sudo ou adicione seu usuário ao grupo docker."
        exit 1
    fi
    ok "Docker OK"
}

check_psql() {
    if ! command -v psql &> /dev/null; then
        warn "psql não encontrado. Tentando instalar..."
        sudo apt-get update -qq && sudo apt-get install -y -qq postgresql-client >/dev/null 2>&1
    fi
    ok "psql OK"
}

# --- Baixar arquivos de migração se não existirem ---
fetch_migration_files() {
    log "Verificando arquivos de migração em $MIGRATION_DIR..."

    if [[ -f "$MIGRATION_DIR/neon_to_local.sql" && -f "$MIGRATION_DIR/neon_data.sql" && -f "$MIGRATION_DIR/docker-compose.yml" ]]; then
        ok "Arquivos já existem localmente"
        return
    fi

    log "Baixando arquivos de migração..."
    mkdir -p "$MIGRATION_DIR"
    cd "$MIGRATION_DIR"

    # Se estiver em um repo git, tenta puxar de lá
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        git pull origin "$BRANCH" -- migration/ 2>/dev/null || true
    fi

    # Fallback: baixa do GitHub raw (ajuste a URL conforme seu repo)
    for file in neon_to_local.sql neon_data.sql docker-compose.yml .env.example README.md neon_inventory.md; do
        if [[ ! -f "$file" ]]; then
            curl -fsSL "https://raw.githubusercontent.com/QuittoGames/coffe_server/main/migration/$file" -o "$file" 2>/dev/null || \
                warn "Não foi possível baixar $file (pode não existir no repo remoto)"
        fi
    done

    # .env local (gera se não existir)
    if [[ ! -f .env ]]; then
        log "Gerando .env local..."
        cat > .env <<'EOF'
POSTGRES_DB=neondb
POSTGRES_USER=neondb_owner
POSTGRES_PASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj
POSTGRES_PORT=5432
EOF
        chmod 600 .env
    fi
    ok "Arquivos prontos"
}

# --- Subir PostgreSQL local ---
start_postgres() {
    log "Subindo PostgreSQL local (docker-compose)..."
    cd "$MIGRATION_DIR"
    docker compose down -v 2>/dev/null || true
    docker compose up -d

    # Aguarda healthcheck
    log "Aguardando PostgreSQL ficar saudável..."
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if docker compose ps --format json | grep -q '"Health":"healthy"'; then
            ok "PostgreSQL saudável"
            return
        fi
        sleep 2
        ((retries--))
    done
    err "Timeout: PostgreSQL não ficou saudável a tempo"
    docker compose logs postgres
    exit 1
}

# --- Aplicar schema ---
apply_schema() {
    log "Aplicando schema (neon_to_local.sql)..."
    cd "$MIGRATION_DIR"
    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql -h localhost -p 5432 -U neondb_owner -d neondb -v ON_ERROR_STOP=1 < neon_to_local.sql
    ok "Schema aplicado"
}

# --- Carregar dados ---
load_data() {
    log "Carregando dados do Neon (neon_data.sql)..."
    cd "$MIGRATION_DIR"
    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql -h localhost -p 5432 -U neondb_owner -d neondb -v ON_ERROR_STOP=1 < neon_data.sql 2>&1 | grep -v "^SET\|^ set_config" || true
    ok "Dados carregados"
}

# --- Corrigir tabela users (conflito de PK) ---
fix_users_table() {
    log "Corrigindo tabela users (conflito de PK com placeholders)..."
    cd "$MIGRATION_DIR"

    # 1. Trunca users (cascata para registry_user_product)
    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql -h localhost -p 5432 -U neondb_owner -d neondb -c "TRUNCATE users RESTART IDENTITY CASCADE;"

    # 2. Recarrega users do Neon (precisa de acesso ao Neon)
    log "Baixando dados reais de 'users' do Neon..."
    PGPASSWORD=npg_sty2oZOQxR7U \
    pg_dump -h ep-snowy-mouse-awycvg31-pooler.c-12.us-east-1.aws.neon.tech \
            -p 5432 -U neondb_owner -d neondb \
            --data-only --table=users --no-owner --no-privileges \
    | PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
      psql -h localhost -p 5432 -U neondb_owner -d neondb

    # 3. Recarrega registry_user_product
    log "Recarregando 'registry_user_product'..."
    PGPASSWORD=npg_sty2oZOQxR7U \
    pg_dump -h ep-snowy-mouse-awycvg31-pooler.c-12.us-east-1.aws.neon.tech \
            -p 5432 -U neondb_owner -d neondb \
            --data-only --table=registry_user_product --no-owner --no-privileges \
    | PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
      psql -h localhost -p 5432 -U neondb_owner -d neondb

    ok "Tabela users corrigida com dados reais do Neon"
}

# --- Validação final ---
validate() {
    log "Validando migração..."
    cd "$MIGRATION_DIR"

    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql -h localhost -p 5432 -U neondb_owner -d neondb -c "
        SELECT 'LOCAL' as src, table_name, COUNT(*) as rows
        FROM information_schema.tables t
        JOIN (
            SELECT 'users' t, COUNT(*) c FROM users
            UNION ALL SELECT 'product', COUNT(*) FROM product
            UNION ALL SELECT 'product_source_observation', COUNT(*) FROM product_source_observation
            UNION ALL SELECT 'registry_user_product', COUNT(*) FROM registry_user_product
            UNION ALL SELECT 'energy_label_class', COUNT(*) FROM energy_label_class
            UNION ALL SELECT 'energy_raw_measurement', COUNT(*) FROM energy_raw_measurement
            UNION ALL SELECT 'energy_specification', COUNT(*) FROM energy_specification
            UNION ALL SELECT 'source_metadata', COUNT(*) FROM source_metadata
            UNION ALL SELECT 'source_product', COUNT(*) FROM source_product
            UNION ALL SELECT 'aggregate_reference', COUNT(*) FROM aggregate_reference
        ) d ON t.table_name = d.t
        WHERE t.table_schema = 'public'
        ORDER BY table_name;
    "

    # Integridade referencial
    PGPASSWORD=pYPCAu9zNUaeQw7oUvWG04tXOV1MIMkj \
    psql -h localhost -p 5432 -U neondb_owner -d neondb -c "
        SELECT 'registry_user_product -> users' chk, COUNT(*) FROM registry_user_product rup JOIN users u ON rup.user_id = u.id
        UNION ALL SELECT 'registry_user_product -> product', COUNT(*) FROM registry_user_product rup JOIN product p ON rup.product_id = p.id
        UNION ALL SELECT 'product_source_observation -> product', COUNT(*) FROM product_source_observation pso JOIN product p ON pso.canonical_product_id = p.id;
    "

    ok "Validação concluída"
}

# --- Main ---
main() {
    echo "============================================================================"
    echo "  NEON → LOCAL POSTGRESQL MIGRATION"
    echo "============================================================================"

    check_docker
    check_psql
    fetch_migration_files
    start_postgres
    apply_schema
    load_data
    fix_users_table
    validate

    echo ""
    echo "============================================================================"
    ok "MIGRAÇÃO CONCLUÍDA COM SUCESSO"
    echo "============================================================================"
    echo ""
    echo "Conexão local:"
    echo "  Host: localhost"
    echo "  Port: 5432"
    echo "  Database: neondb"
    echo "  User: neondb_owner"
    echo "  Password: (ver $MIGRATION_DIR/.env)"
    echo ""
    echo "DATABASE_URL para aplicação:"
    echo "  postgresql://neondb_owner:***@localhost:5432/neondb"
    echo ""
    echo "Para parar:  docker compose -f $MIGRATION_DIR/docker-compose.yml down"
    echo "Para remover tudo (inclui dados): docker compose -f $MIGRATION_DIR/docker-compose.yml down -v"
}

# Executa se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi