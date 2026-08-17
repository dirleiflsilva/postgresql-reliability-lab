#!/usr/bin/env bash
# Teste end-to-end destrutivo. Recria o volume, limpa backups/WALs e executa o
# cenário PITR duas vezes para provar que o lab pode ser repetido.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

if [[ "${1:-}" != "--destructive" ]]; then
  echo "error: este teste recria o volume e apaga backups/WALs do Lab 03." >&2
  echo "uso: scripts/test_repetition.sh --destructive" >&2
  exit 2
fi

wait_for_postgres() {
  echo -n "info: aguardando o PostgreSQL ficar pronto"
  for _ in $(seq 1 60); do
    if docker compose -f "${COMPOSE_FILE}" exec -T postgres \
      pg_isready -h 127.0.0.1 -p 5432 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
      >/dev/null 2>&1; then
      echo
      return 0
    fi
    echo -n "."
    sleep 1
  done
  echo
  echo "error: PostgreSQL não ficou pronto a tempo." >&2
  return 1
}

reset_lab() {
  echo "info: recriando o cluster e removendo artefatos associados..."
  docker compose -f "${COMPOSE_FILE}" down -v
  docker run --rm --user root \
    -v "${LAB_DIR}/wal_archive:/wal_archive" \
    -v "${LAB_DIR}/backups:/backups" \
    postgres:16 bash -c \
    'find /wal_archive /backups/logical /backups/physical -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +'

  ensure_writable_dir "${LAB_DIR}/wal_archive"
  ensure_writable_dir "${LAB_DIR}/backups/logical"
  ensure_writable_dir "${LAB_DIR}/backups/physical"

  docker compose -f "${COMPOSE_FILE}" up -d
  wait_for_postgres
}

echo "info: fase 1/3 - primeira execução completa"
reset_lab
"${SCRIPT_DIR}/check.sh"
"${SCRIPT_DIR}/backup_logical.sh"
"${SCRIPT_DIR}/restore_logical.sh"
"${SCRIPT_DIR}/backup_physical.sh"
"${SCRIPT_DIR}/restore_physical.sh"
"${SCRIPT_DIR}/pitr_demo.sh"
"${SCRIPT_DIR}/restore_physical.sh"

echo "info: fase 2/3 - segundo PITR após reset completo"
reset_lab
"${SCRIPT_DIR}/check.sh"
"${SCRIPT_DIR}/pitr_demo.sh"

echo "info: fase 3/3 - backups parciais e entrada inválida"
reset_lab
"${SCRIPT_DIR}/check.sh"
"${SCRIPT_DIR}/backup_logical.sh"
"${SCRIPT_DIR}/backup_physical.sh"

LOGICAL_PARTIAL="${LAB_DIR}/backups/logical/${POSTGRES_DB}_99999999T999999Z.dump.partial"
PHYSICAL_PARTIAL="${LAB_DIR}/backups/physical/99999999T999999Z.partial"
touch "${LOGICAL_PARTIAL}"
mkdir "${PHYSICAL_PARTIAL}"

cleanup_partial_fixtures() {
  rm -f -- "${LOGICAL_PARTIAL}"
  rmdir -- "${PHYSICAL_PARTIAL}" 2>/dev/null || true
}
trap cleanup_partial_fixtures EXIT

"${SCRIPT_DIR}/restore_logical.sh"
"${SCRIPT_DIR}/restore_physical.sh"

if "${SCRIPT_DIR}/restore_physical.sh" invalid-timestamp >/dev/null 2>&1; then
  echo "error: restore físico aceitou um timestamp inválido." >&2
  exit 1
fi

cleanup_partial_fixtures
trap - EXIT
"${SCRIPT_DIR}/check.sh"

echo "ok: repetição validada (dois PITRs, resets, backups parciais e entrada inválida)."
