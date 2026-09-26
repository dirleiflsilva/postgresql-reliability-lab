#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
mkdir -p "$LAB_DIR/evidence"
run="$(date -u +%Y%m%dT%H%M%SZ)_$RANDOM"
exec > >(tee "$LAB_DIR/evidence/$run.txt") 2>&1
old=''
restore() {
  rc=$?
  trap - EXIT
  if [[ -n "$old" ]]; then compose start "$old" || true; fi
  compose logs --no-color --since 10m pg1 pg2 haproxy > "$LAB_DIR/evidence/$run-containers.log" 2>&1 || true
  exit "$rc"
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
bash "$LAB_DIR/scripts/check.sh"
bash "$LAB_DIR/scripts/status.sh"
old="$(leader)"
new=pg1; [[ "$old" == pg1 ]] && new=pg2
before="before_$run"; after="after_$run"
sql client -c "INSERT INTO audit.failover_probe(token) VALUES ('$before')"
# Barreira explícita: demonstra preservação desta sentinela, não RPO zero.
wait_replay "$new" "$(sql "$old" -Atqc 'SELECT pg_current_wal_flush_lsn()')"
echo "fault_at=$(date -u +%FT%TZ) old_leader=$old candidate=$new"
start=$SECONDS
compose kill -s SIGKILL "$old"
recovered=false
for ((attempt=0; attempt<90; attempt++)); do
  if sql client -c "INSERT INTO audit.failover_probe(token) VALUES ('$after') ON CONFLICT DO NOTHING" >/dev/null 2>&1; then
    recovered=true; break
  fi
  sleep 1
done
[[ "$recovered" == true ]] || { echo 'error: escrita não retomou'; exit 1; }
elapsed=$((SECONDS-start))
[[ "$(leader)" == "$new" ]] || { echo 'error: líder inesperado'; exit 1; }
assert_sql client "SELECT count(*)=2 FROM audit.failover_probe WHERE token IN ('$before','$after')"
echo "recovered_at=$(date -u +%FT%TZ) new_leader=$new write_recovery_seconds=$elapsed"
compose start "$old"
wait_replay "$old" "$(sql "$new" -Atqc 'SELECT pg_current_wal_flush_lsn()')"
assert_sql "$old" "SELECT count(*)=2 FROM audit.failover_probe WHERE token IN ('$before','$after')"
bash "$LAB_DIR/scripts/check.sh"
bash "$LAB_DIR/scripts/status.sh"
echo "ok: failover automático, escrita via HAProxy e reintegração validados; evidência=$run.txt"
