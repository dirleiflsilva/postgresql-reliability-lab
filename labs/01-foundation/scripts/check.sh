#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${LAB_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "error: arquivo ${ENV_FILE} nao encontrado. Crie-o a partir de .env.example."
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker nao esta disponivel no PATH."
  exit 1
fi

if ! docker compose -f "${LAB_DIR}/docker-compose.yml" ps --status running postgres >/dev/null 2>&1; then
  echo "error: container postgres nao esta em execucao. Rode 'docker compose up -d' em ${LAB_DIR}."
  exit 1
fi

if ! docker compose -f "${LAB_DIR}/docker-compose.yml" exec -T postgres \
  pg_isready -h 127.0.0.1 -p 5432 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null; then
  echo "error: postgres nao esta acessivel."
  exit 1
fi

if ! docker compose -f "${LAB_DIR}/docker-compose.yml" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 \
  -c "SELECT id, name, email FROM users ORDER BY id;" >/dev/null; then
  echo "error: query de validacao falhou."
  exit 1
fi

echo "ok: PostgreSQL operacional e tabela users acessivel."
