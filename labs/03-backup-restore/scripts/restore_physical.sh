#!/usr/bin/env bash
# Sobe um Postgres temporário e independente a partir de um backup físico
# (pg_basebackup) para validar que ele inicializa e serve os dados esperados.
# Uso: scripts/restore_physical.sh [TIMESTAMP]
# Sem argumento, usa o backup físico mais recente em backups/physical/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

TIMESTAMP="${1:-}"
PHYSICAL_DIR="${LAB_DIR}/backups/physical"
ensure_writable_dir "${PHYSICAL_DIR}"

if [[ -z "${TIMESTAMP}" ]]; then
  TIMESTAMP="$(find "${PHYSICAL_DIR}" -maxdepth 1 -mindepth 1 -type d -not -name '*-verify' -printf '%f\n' | sort -r | head -n1)"
  if [[ -z "${TIMESTAMP}" ]]; then
    echo "error: nenhum backup físico encontrado em backups/physical/. Rode backup_physical.sh primeiro."
    exit 1
  fi
fi

SRC_DIR="${PHYSICAL_DIR}/${TIMESTAMP}"
VERIFY_DIR="${PHYSICAL_DIR}/${TIMESTAMP}-verify"
CONTAINER_NAME="pgrl-backup-restore-verify-physical"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "error: backups/physical/${TIMESTAMP} não encontrado."
  exit 1
fi

echo "info: copiando backups/physical/${TIMESTAMP} para uma área de verificação isolada..."
# O diretório do backup pertence ao usuário "postgres" (uid 999) dentro do
# container, com permissão 0700 — por isso a cópia roda como root dentro de
# um container auxiliar, e não diretamente no host.
docker run --rm --user root -v "${PHYSICAL_DIR}:/physical" postgres:16 \
  bash -c "rm -rf '/physical/${TIMESTAMP}-verify' && cp -a '/physical/${TIMESTAMP}' '/physical/${TIMESTAMP}-verify'"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "info: subindo container temporário a partir do backup físico..."
docker run -d --name "${CONTAINER_NAME}" \
  -p "${VERIFY_PHYSICAL_PORT}:5432" \
  -v "${VERIFY_DIR}:/var/lib/postgresql/data" \
  postgres:16 >/dev/null

echo -n "info: aguardando o cluster restaurado ficar pronto"
READY=0
for _ in $(seq 1 30); do
  if docker exec "${CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
    READY=1
    break
  fi
  echo -n "."
  sleep 2
done
echo

if [[ "${READY}" -ne 1 ]]; then
  echo "error: cluster restaurado não ficou pronto a tempo. Logs:"
  docker logs "${CONTAINER_NAME}" | tail -n 50
  exit 1
fi

echo "info: validando dados no cluster restaurado (porta ${VERIFY_PHYSICAL_PORT})..."
docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
DO $$
BEGIN
  IF (SELECT count(*) FROM app.customers) < 100 THEN
    RAISE EXCEPTION 'customers abaixo do esperado no backup físico restaurado';
  END IF;

  IF (SELECT count(*) FROM app.orders) < 500 THEN
    RAISE EXCEPTION 'orders abaixo do esperado no backup físico restaurado';
  END IF;
END
$$;
SQL

echo "ok: backup físico backups/physical/${TIMESTAMP} restaurado e validado com sucesso."
echo "info: container temporário será removido automaticamente ao final deste script."
