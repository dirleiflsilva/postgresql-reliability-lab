#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
primary="$(leader)"
replica=pg1; [[ "$primary" == pg1 ]] && replica=pg2
assert_sql "$primary" 'SELECT NOT pg_is_in_recovery()'
assert_sql "$replica" 'SELECT pg_is_in_recovery()'
assert_sql client 'SELECT NOT pg_is_in_recovery()'
assert_sql "$primary" "SELECT count(*) = 1 FROM pg_stat_replication WHERE state='streaming' AND sync_state='async'"
assert_sql "$primary" 'SELECT (SELECT count(*) FROM app.customers)=100 AND (SELECT count(*) FROM app.orders)=500'
token="check_$(date +%s)_$RANDOM"
sql client -v token="$token" <<'SQL'
INSERT INTO audit.failover_probe(token) VALUES (:'token');
SQL
wait_replay "$replica" "$(sql "$primary" -Atqc 'SELECT pg_current_wal_flush_lsn()')"
assert_sql "$replica" "SELECT EXISTS (SELECT FROM audit.failover_probe WHERE token='$token')"
# A escrita deve falhar especificamente por read-only, não por erro de conexão.
if output="$(sql "$replica" -v VERBOSITY=verbose -c "INSERT INTO audit.failover_probe(token) VALUES ('forbidden_$token')" 2>&1)"; then
  echo 'error: réplica aceitou escrita' >&2; exit 1
fi
[[ "$output" == *25006* ]] || { echo "$output" >&2; exit 1; }
for node in etcd1 etcd2 etcd3; do
  compose exec -T "$node" etcdctl --endpoints=http://localhost:2379 endpoint health
done
sql client -c "DELETE FROM audit.failover_probe WHERE token='$token'"
echo "ok: líder=$primary réplica=$replica; endpoint, dados, streaming, read-only e etcd validados."
