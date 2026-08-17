#!/usr/bin/env bash
# Gera um backup físico (base backup) via pg_basebackup, usando backup_user
# (role criada em init/01_roles.sql com atributo REPLICATION).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
require_running_postgres

ensure_writable_dir "${LAB_DIR}/backups/physical"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET_DIR="/backups/physical/${TIMESTAMP}"
PARTIAL_DIR="${TARGET_DIR}.partial"
HOST_TARGET_DIR="${LAB_DIR}${TARGET_DIR}"
HOST_PARTIAL_DIR="${LAB_DIR}${PARTIAL_DIR}"

if [[ -e "${HOST_TARGET_DIR}" || -e "${HOST_PARTIAL_DIR}" ]]; then
  echo "error: já existe um backup ou backup parcial para o timestamp ${TIMESTAMP}."
  exit 1
fi

echo "info: gerando backup físico em backups/physical/${TIMESTAMP}..."

docker compose -f "${COMPOSE_FILE}" exec -T --user postgres \
  -e PGPASSWORD="${BACKUP_USER_PASSWORD}" \
  postgres pg_basebackup \
    -h 127.0.0.1 -p 5432 -U "${BACKUP_USER}" \
    -D "${PARTIAL_DIR}" -Fp -Xs -P

mv -- "${HOST_PARTIAL_DIR}" "${HOST_TARGET_DIR}"

echo "ok: backup físico criado em backups/physical/${TIMESTAMP}"
echo "info: use este nome de diretório com scripts/restore_physical.sh ${TIMESTAMP}"
