#!/usr/bin/env bash
# Restaura o dump lógico mais recente (ou o informado como argumento) em um
# banco separado (${POSTGRES_DB}_restore) e compara a contagem de linhas por
# tabela contra o banco de origem.
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

echo "info: restaurando ${DUMP_FILE#/backups/logical/} em ${RESTORE_DB}..."

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${RESTORE_DB};" >/dev/null
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${RESTORE_DB};" >/dev/null

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  pg_restore -U "${POSTGRES_USER}" -d "${RESTORE_DB}" --no-owner "${DUMP_FILE}"

echo "info: comparando contagem de linhas entre ${POSTGRES_DB} e ${RESTORE_DB}..."

TABLES=(app.customers app.addresses app.categories app.products app.orders app.order_items app.payments audit.events)
MISMATCH=0

for TABLE in "${TABLES[@]}"; do
  ORIGINAL_COUNT="$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT count(*) FROM ${TABLE};")"
  RESTORED_COUNT="$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${RESTORE_DB}" -t -A -c "SELECT count(*) FROM ${TABLE};")"

  if [[ "${ORIGINAL_COUNT}" != "${RESTORED_COUNT}" ]]; then
    echo "error: divergência em ${TABLE}: origem=${ORIGINAL_COUNT} restaurado=${RESTORED_COUNT}"
    MISMATCH=1
  else
    echo "ok: ${TABLE} (${RESTORED_COUNT} linhas)"
  fi
done

if [[ "${MISMATCH}" -ne 0 ]]; then
  echo "error: restore lógico divergente do banco de origem."
  exit 1
fi

echo "ok: restore lógico validado em ${RESTORE_DB}, todas as tabelas batem com ${POSTGRES_DB}."
