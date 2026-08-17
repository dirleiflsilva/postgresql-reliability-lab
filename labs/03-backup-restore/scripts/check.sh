#!/usr/bin/env bash
# Valida o estado base do ambiente (roles, schemas, extensões, dados e
# configuração de WAL archiving). Não exercita backup/restore/PITR — isso é
# feito pelos scripts backup_logical.sh, restore_logical.sh, backup_physical.sh,
# restore_physical.sh e pitr_demo.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
require_running_postgres

if ! docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  pg_isready -h 127.0.0.1 -p 5432 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null; then
  echo "error: postgres não está acessível."
  exit 1
fi

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_roles WHERE rolname IN ('app_owner', 'app_user', 'readonly', 'backup_user', 'monitor_user')) <> 5 THEN
    RAISE EXCEPTION 'roles esperadas não foram criadas';
  END IF;

  IF NOT (SELECT rolreplication FROM pg_roles WHERE rolname = 'backup_user') THEN
    RAISE EXCEPTION 'backup_user não possui atributo REPLICATION';
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

  IF (SELECT count(*) FROM app.orders) < 1 THEN
    RAISE EXCEPTION 'orders abaixo do esperado (rode "docker compose down -v && up -d" se já executou o pitr_demo.sh)';
  END IF;

  IF current_setting('archive_mode') <> 'on' THEN
    RAISE EXCEPTION 'archive_mode não está habilitado';
  END IF;

  IF current_setting('wal_level') <> 'replica' THEN
    RAISE EXCEPTION 'wal_level não está configurado como replica';
  END IF;
END
$$;
SQL

echo "ok: backup & restore validado (roles, schemas, extensões, dados e WAL archiving)."
