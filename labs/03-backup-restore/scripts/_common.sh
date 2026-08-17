#!/usr/bin/env bash
# Carregado (source) pelos demais scripts do lab. Não é executado diretamente.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${LAB_DIR}/.env"
COMPOSE_FILE="${LAB_DIR}/docker-compose.yml"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "error: arquivo ${ENV_FILE} não encontrado. Crie-o a partir de .env.example."
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker não está disponível no PATH."
  exit 1
fi

require_running_postgres() {
  if ! docker compose -f "${COMPOSE_FILE}" ps --status running --services | grep -qx "postgres"; then
    echo "error: container postgres não está em execução. Rode 'docker compose up -d' em ${LAB_DIR}."
    exit 1
  fi
}

# Bind mounts podem atravessar user namespaces e apresentar UIDs diferentes no
# host e no container. O modo 1733 mantém listagem/leitura restrita ao dono do
# diretório, permite escrita ao postgres e usa sticky bit para impedir que um
# terceiro uid remova arquivos que não lhe pertencem.
ensure_writable_dir() {
  mkdir -p -- "$1"
  chmod 1733 "$1"
}

validate_compose_database() {
  local database="$1"
  docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${database}" -X -v ON_ERROR_STOP=1 \
    <"${SCRIPT_DIR}/validate_restored_db.sql"
}

validate_container_database() {
  local container="$1"
  local database="$2"
  docker exec -i "${container}" \
    psql -U "${POSTGRES_USER}" -d "${database}" -X -v ON_ERROR_STOP=1 \
    <"${SCRIPT_DIR}/validate_restored_db.sql"
}

fingerprint_compose_database() {
  local database="$1"
  docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${database}" -X -t -A -v ON_ERROR_STOP=1 \
    <"${SCRIPT_DIR}/orders_fingerprint.sql"
}

fingerprint_container_database() {
  local container="$1"
  local database="$2"
  docker exec -i "${container}" \
    psql -U "${POSTGRES_USER}" -d "${database}" -X -t -A -v ON_ERROR_STOP=1 \
    <"${SCRIPT_DIR}/orders_fingerprint.sql"
}
