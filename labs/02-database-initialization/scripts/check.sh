#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${LAB_DIR}/.env"

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

if ! docker compose -f "${LAB_DIR}/docker-compose.yml" ps --status running --services | grep -qx "postgres"; then
  echo "error: container postgres não está em execução. Rode 'docker compose up -d' em ${LAB_DIR}."
  exit 1
fi

if ! docker compose -f "${LAB_DIR}/docker-compose.yml" exec -T postgres \
  pg_isready -h 127.0.0.1 -p 5432 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null; then
  echo "error: postgres não está acessível."
  exit 1
fi

docker compose -f "${LAB_DIR}/docker-compose.yml" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_roles WHERE rolname IN ('app_owner', 'app_user', 'readonly', 'backup_user', 'monitor_user')) <> 5 THEN
    RAISE EXCEPTION 'roles esperadas não foram criadas';
  END IF;

  IF (SELECT count(*) FROM pg_namespace WHERE nspname IN ('app', 'audit', 'seed')) <> 3 THEN
    RAISE EXCEPTION 'schemas esperados não foram criados';
  END IF;

  IF (SELECT count(*) FROM pg_extension WHERE extname IN ('pg_stat_statements', 'pgcrypto', 'uuid-ossp')) <> 3 THEN
    RAISE EXCEPTION 'extensões esperadas não foram criadas';
  END IF;

  IF (SELECT count(*) FROM app.customers) < 100 THEN
    RAISE EXCEPTION 'customers abaixo do esperado';
  END IF;

  IF (SELECT count(*) FROM app.products) < 50 THEN
    RAISE EXCEPTION 'products abaixo do esperado';
  END IF;

  IF (SELECT count(*) FROM app.orders) < 500 THEN
    RAISE EXCEPTION 'orders abaixo do esperado';
  END IF;

  IF (SELECT count(*) FROM app.order_items) < 500 THEN
    RAISE EXCEPTION 'order_items abaixo do esperado';
  END IF;

  IF (SELECT count(*) FROM app.payments) < 500 THEN
    RAISE EXCEPTION 'payments abaixo do esperado';
  END IF;

  IF (SELECT count(*) FROM audit.events) < 500 THEN
    RAISE EXCEPTION 'audit.events abaixo do esperado';
  END IF;
END
$$;
SQL

echo "ok: database initialization validado com roles, schemas, extensões, tabelas e dados."
