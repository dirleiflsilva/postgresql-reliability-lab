#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
require_running_postgres

ensure_writable_dir "${LAB_DIR}/backups/logical"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DUMP_NAME="${POSTGRES_DB}_${TIMESTAMP}.dump"
DUMP_FILE="/backups/logical/${DUMP_NAME}"
PARTIAL_FILE="${DUMP_FILE}.partial"
HOST_DUMP_FILE="${LAB_DIR}${DUMP_FILE}"
HOST_PARTIAL_FILE="${LAB_DIR}${PARTIAL_FILE}"

if [[ -e "${HOST_DUMP_FILE}" || -e "${HOST_PARTIAL_FILE}" ]]; then
  echo "error: já existe um backup ou backup parcial para o timestamp ${TIMESTAMP}."
  exit 1
fi

cleanup() {
  rm -f -- "${HOST_PARTIAL_FILE}"
}
trap cleanup EXIT

echo "info: gerando backup lógico de ${POSTGRES_DB} em backups/logical/${POSTGRES_DB}_${TIMESTAMP}.dump..."

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc -f "${PARTIAL_FILE}"

mv -- "${HOST_PARTIAL_FILE}" "${HOST_DUMP_FILE}"
trap - EXIT

echo "ok: backup lógico criado em backups/logical/${DUMP_NAME}"
