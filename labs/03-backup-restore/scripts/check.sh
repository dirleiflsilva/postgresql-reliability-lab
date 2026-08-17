#!/usr/bin/env bash
# Valida o estado base do ambiente e força um WAL switch para comprovar que o
# archive_command publica o segmento. Não exercita backup/restore/PITR — isso é
# feito pelos demais scripts do lab.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
require_running_postgres

WAL_ARCHIVE_DIR="${LAB_DIR}/wal_archive"
ensure_writable_dir "${WAL_ARCHIVE_DIR}"

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
    RAISE EXCEPTION 'orders abaixo do esperado (siga o reset completo do README se já executou o pitr_demo.sh)';
  END IF;

  IF current_setting('archive_mode') <> 'on' THEN
    RAISE EXCEPTION 'archive_mode não está habilitado';
  END IF;

  IF current_setting('wal_level') <> 'replica' THEN
    RAISE EXCEPTION 'wal_level não está configurado como replica';
  END IF;

  IF current_setting('archive_command') <> '/usr/local/bin/archive_wal %p %f' THEN
    RAISE EXCEPTION 'archive_command não aponta para o helper esperado';
  END IF;
END
$$;
SQL

if ! docker compose -f "${COMPOSE_FILE}" exec -T --user postgres postgres \
  test -w /var/lib/postgresql/wal_archive; then
  echo "error: diretório de WAL archive não está gravável pelo usuário postgres."
  exit 1
fi

IFS='|' read -r CHECK_WAL ARCHIVED_BEFORE FAILED_BEFORE <<<"$(
  docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -X -t -A -F '|' -c \
      "SELECT pg_walfile_name(pg_current_wal_lsn()), archived_count, failed_count FROM pg_stat_archiver;"
)"

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -X -t -A \
    -c "SELECT pg_switch_wal();" >/dev/null

ARCHIVED_NOW="${ARCHIVED_BEFORE}"
FAILED_NOW="${FAILED_BEFORE}"
WAL_ARCHIVED=0
for _ in $(seq 1 30); do
  IFS='|' read -r ARCHIVED_NOW FAILED_NOW <<<"$(
    docker compose -f "${COMPOSE_FILE}" exec -T postgres \
      psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -X -t -A -F '|' -c \
        "SELECT archived_count, failed_count FROM pg_stat_archiver;"
  )"

  if (( ARCHIVED_NOW > ARCHIVED_BEFORE )) \
    && [[ -f "${WAL_ARCHIVE_DIR}/${CHECK_WAL}" ]]; then
    WAL_ARCHIVED=1
    break
  fi

  sleep 1
done

if [[ "${WAL_ARCHIVED}" -ne 1 ]]; then
  echo "error: WAL ${CHECK_WAL} não foi confirmado no archive a tempo."
  echo "info: pg_stat_archiver antes: archived=${ARCHIVED_BEFORE}, failed=${FAILED_BEFORE}"
  echo "info: pg_stat_archiver agora: archived=${ARCHIVED_NOW}, failed=${FAILED_NOW}"
  exit 1
fi

if (( FAILED_NOW > FAILED_BEFORE )); then
  echo "error: o archiver registrou nova falha durante a validação."
  exit 1
fi

echo "ok: backup & restore validado (roles, schemas, extensões, dados e arquivamento real de WAL)."
