#!/usr/bin/env bash
# Restaura o dump lógico mais recente (ou o informado como argumento) em um
# banco separado (${POSTGRES_DB}_restore), valida estrutura e integridade e
# apresenta apenas uma comparação informativa com o banco atual.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
require_running_postgres

ensure_writable_dir "${LAB_DIR}/backups/logical"

DUMP_ARG="${1:-}"
RESTORE_DB="${POSTGRES_DB}_restore"

if [[ -n "${DUMP_ARG}" ]]; then
  DUMP_FILE="/backups/logical/${DUMP_ARG}"
  if [[ ! -f "${LAB_DIR}/backups/logical/${DUMP_ARG}" ]]; then
    echo "error: arquivo backups/logical/${DUMP_ARG} não encontrado."
    exit 1
  fi
else
  LATEST="$(ls -1t "${LAB_DIR}/backups/logical" | grep '\.dump$' | head -n1 || true)"
  if [[ -z "${LATEST}" ]]; then
    echo "error: nenhum dump encontrado em backups/logical/. Rode backup_logical.sh primeiro."
    exit 1
  fi
  DUMP_FILE="/backups/logical/${LATEST}"
fi

echo "info: validando catálogo do dump ${DUMP_FILE#/backups/logical/}..."
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  pg_restore --list "${DUMP_FILE}" >/dev/null

echo "info: restaurando ${DUMP_FILE#/backups/logical/} em ${RESTORE_DB}..."

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d postgres -X -v ON_ERROR_STOP=1 \
    -v restore_db="${RESTORE_DB}" <<'SQL' >/dev/null
DO $roles$
DECLARE
  missing_roles text;
BEGIN
  SELECT string_agg(required_role, ', ' ORDER BY required_role)
  INTO missing_roles
  FROM unnest(ARRAY['app_owner', 'app_user', 'readonly', 'backup_user', 'monitor_user']) AS required_role
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = required_role
  );

  IF missing_roles IS NOT NULL THEN
    RAISE EXCEPTION 'roles globais ausentes: %. Execute init/01_roles.sql antes do restore', missing_roles;
  END IF;
END
$roles$;

SELECT format('DROP DATABASE IF EXISTS %I', :'restore_db') \gexec
SELECT format('CREATE DATABASE %I TEMPLATE template0', :'restore_db') \gexec
SQL

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  pg_restore -U "${POSTGRES_USER}" -d "${RESTORE_DB}" "${DUMP_FILE}"

echo "info: validando estrutura, conteúdo sentinela e integridade em ${RESTORE_DB}..."
validate_compose_database "${RESTORE_DB}" >/dev/null

echo "info: comparação informativa entre o banco atual e o snapshot restaurado:"

TABLES=(app.customers app.addresses app.categories app.products app.orders app.order_items app.payments audit.events)

for TABLE in "${TABLES[@]}"; do
  ORIGINAL_COUNT="$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT count(*) FROM ${TABLE};")"
  RESTORED_COUNT="$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${RESTORE_DB}" -t -A -c "SELECT count(*) FROM ${TABLE};")"

  if [[ "${ORIGINAL_COUNT}" != "${RESTORED_COUNT}" ]]; then
    echo "info: ${TABLE}: atual=${ORIGINAL_COUNT}, snapshot=${RESTORED_COUNT} (estados diferentes)"
  else
    echo "ok: ${TABLE} (${RESTORED_COUNT} linhas)"
  fi
done

CURRENT_FINGERPRINT="$(fingerprint_compose_database "${POSTGRES_DB}")"
RESTORED_FINGERPRINT="$(fingerprint_compose_database "${RESTORE_DB}")"

if [[ "${CURRENT_FINGERPRINT}" == "${RESTORED_FINGERPRINT}" ]]; then
  echo "ok: fingerprint de pedidos coincide com o banco atual (${RESTORED_FINGERPRINT})."
else
  echo "info: fingerprint atual=${CURRENT_FINGERPRINT:-<vazio>}"
  echo "info: fingerprint do snapshot=${RESTORED_FINGERPRINT:-<vazio>}"
  echo "info: a diferença é informativa e não invalida o restore de um snapshot anterior."
fi

echo "ok: restore lógico validado em ${RESTORE_DB} pelo catálogo do dump, estrutura e integridade dos dados."
