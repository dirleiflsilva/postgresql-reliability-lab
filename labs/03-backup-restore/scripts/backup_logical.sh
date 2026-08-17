#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
require_running_postgres

ensure_writable_dir "${LAB_DIR}/backups/logical"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DUMP_FILE="/backups/logical/${POSTGRES_DB}_${TIMESTAMP}.dump"

echo "info: gerando backup lógico de ${POSTGRES_DB} em backups/logical/${POSTGRES_DB}_${TIMESTAMP}.dump..."

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc -f "${DUMP_FILE}"

echo "ok: backup lógico criado em backups/logical/${POSTGRES_DB}_${TIMESTAMP}.dump"
