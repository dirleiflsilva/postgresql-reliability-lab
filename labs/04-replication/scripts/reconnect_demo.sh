#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
bash "$LAB_DIR/scripts/check.sh"
restore_replica() { compose start replica >/dev/null || true; }
trap restore_replica EXIT
compose stop replica
token="reconnect-$(date +%s%N)-$$"
sql primary -v token="$token" <<'SQL'
INSERT INTO audit.replication_probe(token) VALUES (:'token');
SQL
lsn=$(sql primary -Atqc 'SELECT pg_current_wal_flush_lsn()')
assert_sql primary "SELECT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name='lab04_replica' AND NOT active)"
compose start replica
wait_replay "$lsn"
assert_sql replica "SELECT EXISTS (SELECT FROM audit.replication_probe WHERE token='$token')"
sql primary -v token="$token" <<'SQL'
DELETE FROM audit.replication_probe WHERE token=:'token';
SQL
trap - EXIT
bash "$LAB_DIR/scripts/check.sh"
echo 'ok: escrita com réplica parada e recuperação após reconexão validadas.'
