#!/usr/bin/env bash
# Copia um WAL para o archive sem sobrescrever conteúdo diferente. Se o mesmo
# WAL já estiver arquivado com conteúdo idêntico, considera a operação bem-sucedida.
set -euo pipefail

SOURCE_FILE="${1:-}"
WAL_NAME="${2:-}"
ARCHIVE_DIR="${3:-/var/lib/postgresql/wal_archive}"

if [[ -z "${SOURCE_FILE}" || -z "${WAL_NAME}" ]]; then
  echo "error: uso: archive_wal.sh SOURCE_FILE WAL_NAME [ARCHIVE_DIR]" >&2
  exit 2
fi

if [[ ! -f "${SOURCE_FILE}" ]]; then
  echo "error: WAL de origem não encontrado: ${SOURCE_FILE}" >&2
  exit 1
fi

if [[ ! "${WAL_NAME}" =~ ^[[:alnum:].]{1,64}$ || "${WAL_NAME}" == .* ]]; then
  echo "error: nome de WAL inválido: ${WAL_NAME}" >&2
  exit 2
fi

if [[ ! -d "${ARCHIVE_DIR}" || ! -w "${ARCHIVE_DIR}" ]]; then
  echo "error: diretório de archive ausente ou sem permissão de escrita: ${ARCHIVE_DIR}" >&2
  exit 1
fi

DEST_FILE="${ARCHIVE_DIR}/${WAL_NAME}"
TEMP_FILE="${DEST_FILE}.tmp.$$"

cleanup() {
  rm -f -- "${TEMP_FILE}"
}
trap cleanup EXIT

if [[ -e "${DEST_FILE}" ]]; then
  if cmp -s -- "${SOURCE_FILE}" "${DEST_FILE}"; then
    exit 0
  fi

  echo "error: archive já contém ${WAL_NAME} com conteúdo diferente" >&2
  exit 1
fi

cp -- "${SOURCE_FILE}" "${TEMP_FILE}"
chmod 600 "${TEMP_FILE}"
sync -f "${TEMP_FILE}"

# O hard link publica o arquivo de forma atômica e falha se outro processo tiver
# criado o destino entre a verificação acima e este ponto.
if ln -- "${TEMP_FILE}" "${DEST_FILE}" 2>/dev/null; then
  rm -f -- "${TEMP_FILE}"
  trap - EXIT
  # syncfs pelo arquivo final também persiste a entrada do diretório, sem exigir
  # permissão de listagem no diretório 1733.
  sync -f "${DEST_FILE}"
  exit 0
fi

if [[ -e "${DEST_FILE}" ]] && cmp -s -- "${SOURCE_FILE}" "${DEST_FILE}"; then
  exit 0
fi

echo "error: não foi possível publicar ${WAL_NAME} no archive" >&2
exit 1
