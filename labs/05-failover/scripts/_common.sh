#!/usr/bin/env bash
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$LAB_DIR/.env" ]] || { echo 'error: crie .env a partir de .env.example.' >&2; exit 1; }
compose() { docker compose --project-directory "$LAB_DIR" -f "$LAB_DIR/docker-compose.yml" "$@"; }
sql() { local node="$1"; shift; compose exec -T "$node" psql -X -v ON_ERROR_STOP=1 -U postgres -d appdb "$@"; }
assert_sql() { [[ "$(sql "$1" -Atqc "$2")" == t ]] || { echo "error: assertion $1: $2" >&2; return 1; }; }
leader() {
  local node found=''
  for node in pg1 pg2; do
    if compose exec -T client curl -fsS --max-time 2 "http://$node:8008/primary" >/dev/null 2>&1; then
      [[ -z "$found" ]] || { echo 'error: mais de um líder' >&2; return 1; }
      found="$node"
    fi
  done
  [[ -n "$found" ]] || return 1
  echo "$found"
}
wait_replay() {
  local node="$1" lsn="$2"
  [[ "$lsn" =~ ^[0-9A-F]+/[0-9A-F]+$ ]] || return 1
  for ((i=0; i<60; i++)); do
    if [[ "$(sql "$node" -Atqc "SELECT pg_is_in_recovery() AND pg_last_wal_replay_lsn() >= '$lsn'::pg_lsn" 2>/dev/null)" == t ]]; then return 0; fi
    sleep 1
  done
  echo "error: $node não alcançou $lsn" >&2; return 1
}
