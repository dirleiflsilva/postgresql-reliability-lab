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

# O processo do PostgreSQL dentro do container roda como o usuário "postgres"
# (uid 999), diferente do usuário do host que criou o diretório via bind
# mount. Por isso os diretórios usados para backup/WAL archive precisam ficar
# graváveis por qualquer uid.
ensure_writable_dir() {
  mkdir -p "$1"
  chmod 777 "$1"
}
