#!/usr/bin/env bash
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$LAB_DIR/.env" ]] || { echo 'error: crie .env a partir de .env.example.' >&2; exit 1; }
compose() { docker compose --project-directory "$LAB_DIR" -f "$LAB_DIR/docker-compose.yml" "$@"; }
sql() {
  local service="$1"; shift
  compose exec -T "$service" sh -c 'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"' sh "$@"
}
assert_sql() {
  local service="$1" query="$2"
  [[ "$(sql "$service" -Atqc "$query")" == t ]] || {
    echo "error: validação falhou em $service: $query" >&2; return 1;
  }
}
wait_replay() {
  local lsn="$1"
  [[ "$lsn" =~ ^[0-9A-F]+/[0-9A-F]+$ ]] || return 1
  for ((attempt=0; attempt<60; attempt++)); do
    if [[ "$(sql replica -Atqc "SELECT pg_is_in_recovery() AND pg_last_wal_replay_lsn() >= '$lsn'::pg_lsn" 2>/dev/null)" == t ]]; then
      return 0
    fi
    sleep 1
  done
  echo "error: réplica não alcançou o LSN $lsn em 60s." >&2
  return 1
}
probe() {
  local token="$1"
  sql primary -v token="$token" <<'SQL'
INSERT INTO audit.replication_probe(token) VALUES (:'token');
SQL
  wait_replay "$(sql primary -Atqc 'SELECT pg_current_wal_flush_lsn()')"
  assert_sql replica "SELECT EXISTS (SELECT FROM audit.replication_probe WHERE token = '$token')"
}
