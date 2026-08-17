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

echo "info: gerando backup físico em backups/physical/${TIMESTAMP}..."

docker compose -f "${COMPOSE_FILE}" exec -T --user postgres \
  -e PGPASSWORD="${BACKUP_USER_PASSWORD}" \
  postgres pg_basebackup \
    -h 127.0.0.1 -p 5432 -U "${BACKUP_USER}" \
    -D "${TARGET_DIR}" -Fp -Xs -P

echo "ok: backup físico criado em backups/physical/${TIMESTAMP}"
echo "info: use este nome de diretório com scripts/restore_physical.sh ${TIMESTAMP}"
