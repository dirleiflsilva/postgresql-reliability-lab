#!/usr/bin/env bash
# Roteiro guiado de Point-in-Time Recovery (PITR):
#   1. tira um backup físico de base
#   2. registra um timestamp de referência
#   3. simula um incidente (apaga pedidos) no ambiente principal do lab
#   4. restaura o backup em um container isolado, reproduzindo os WALs
#      arquivados até o timestamp de referência
#   5. compara os dados restaurados com o estado anterior ao incidente
#
# ATENÇÃO: este script apaga dados de app.orders/app.order_items/app.payments
# no ambiente principal do lab para simular o incidente. Isso é intencional
# (é o objetivo da demonstração). Para voltar ao estado original, recrie o
# volume do lab com `docker compose down -v && docker compose up -d`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
require_running_postgres

PHYSICAL_DIR="${LAB_DIR}/backups/physical"
WAL_ARCHIVE_DIR="${LAB_DIR}/wal_archive"
CONTAINER_NAME="pgrl-backup-restore-verify-pitr"
ensure_writable_dir "${PHYSICAL_DIR}"
ensure_writable_dir "${WAL_ARCHIVE_DIR}"

echo "info: verificando se archive_mode está ativo..."
ARCHIVE_MODE="$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SHOW archive_mode;")"
if [[ "${ARCHIVE_MODE}" != "on" ]]; then
  echo "error: archive_mode não está 'on' (valor atual: ${ARCHIVE_MODE})."
  exit 1
fi

echo "info: 1/5 - gerando backup físico de base para o PITR..."
BASE_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE_DIR="/backups/physical/${BASE_TIMESTAMP}"
docker compose -f "${COMPOSE_FILE}" exec -T --user postgres \
  -e PGPASSWORD="${BACKUP_USER_PASSWORD}" \
  postgres pg_basebackup \
    -h 127.0.0.1 -p 5432 -U "${BACKUP_USER}" \
    -D "${BASE_DIR}" -Fp -Xs -P

BASELINE_COUNT="$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT count(*) FROM app.orders;")"
echo "info: app.orders antes do incidente: ${BASELINE_COUNT} linhas"

sleep 2
REFERENCE_TIME="$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS.US TZ');" | xargs)"
echo "info: 2/5 - timestamp de referência para o PITR: ${REFERENCE_TIME}"
sleep 2

echo "info: 3/5 - simulando incidente (apagando pedidos no ambiente principal)..."
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
DELETE FROM app.payments;
DELETE FROM app.order_items;
DELETE FROM app.orders;
SQL

docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT pg_switch_wal();" >/dev/null

POST_INCIDENT_COUNT="$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT count(*) FROM app.orders;")"
echo "info: app.orders após o incidente (no ambiente principal): ${POST_INCIDENT_COUNT} linhas"

echo "info: 4/5 - restaurando o backup de base com recovery_target_time=${REFERENCE_TIME}..."
PITR_DIR="${PHYSICAL_DIR}/${BASE_TIMESTAMP}-pitr"

# O diretório do backup pertence ao usuário "postgres" (uid 999) dentro do
# container, com permissão 0700 — por isso cópia, recovery.signal e o ajuste
# de postgresql.auto.conf rodam como root dentro de um container auxiliar,
# e não diretamente no host.
CONF_SNIPPET="$(mktemp)"
cat >"${CONF_SNIPPET}" <<EOF
restore_command = 'cp /wal_archive/%f %p'
recovery_target_time = '${REFERENCE_TIME}'
recovery_target_action = 'promote'
EOF

docker run --rm --user root \
  -v "${PHYSICAL_DIR}:/physical" \
  -v "${CONF_SNIPPET}:/tmp/recovery.conf.snippet:ro" \
  postgres:16 bash -c "
    rm -rf '/physical/${BASE_TIMESTAMP}-pitr' &&
    cp -a '/physical/${BASE_TIMESTAMP}' '/physical/${BASE_TIMESTAMP}-pitr' &&
    touch '/physical/${BASE_TIMESTAMP}-pitr/recovery.signal' &&
    cat /tmp/recovery.conf.snippet >> '/physical/${BASE_TIMESTAMP}-pitr/postgresql.auto.conf'
  "
rm -f "${CONF_SNIPPET}"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "${CONTAINER_NAME}" \
  -p "${VERIFY_PITR_PORT}:5432" \
  -v "${PITR_DIR}:/var/lib/postgresql/data" \
  -v "${WAL_ARCHIVE_DIR}:/wal_archive:ro" \
  postgres:16 >/dev/null

echo -n "info: aguardando a recuperação (replay de WAL) terminar e o cluster promover"
PROMOTED=0
for _ in $(seq 1 60); do
  if docker exec "${CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
    IN_RECOVERY="$(docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT pg_is_in_recovery();" 2>/dev/null || echo "t")"
    if [[ "${IN_RECOVERY}" == "f" ]]; then
      PROMOTED=1
      break
    fi
  fi
  echo -n "."
  sleep 2
done
echo

if [[ "${PROMOTED}" -ne 1 ]]; then
  echo "error: cluster restaurado não promoveu a tempo. Logs:"
  docker logs "${CONTAINER_NAME}" | tail -n 80
  exit 1
fi

RESTORED_COUNT="$(docker exec "${CONTAINER_NAME}" \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT count(*) FROM app.orders;")"

echo "info: 5/5 - resultado da recuperação (porta ${VERIFY_PITR_PORT}):"
echo "  app.orders antes do incidente ......... ${BASELINE_COUNT}"
echo "  app.orders após o incidente (live) .... ${POST_INCIDENT_COUNT}"
echo "  app.orders restaurado via PITR ........ ${RESTORED_COUNT}"

if [[ "${RESTORED_COUNT}" != "${BASELINE_COUNT}" ]]; then
  echo "error: PITR não restaurou a contagem esperada de app.orders."
  exit 1
fi

echo "ok: PITR validado — dados restaurados para o instante anterior ao incidente."
echo "info: container temporário será removido automaticamente ao final deste script."
echo "info: para repor o ambiente principal do lab, rode 'docker compose down -v && docker compose up -d'."
