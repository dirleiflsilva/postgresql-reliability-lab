#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
assert_sql primary 'SELECT NOT pg_is_in_recovery()'
assert_sql replica 'SELECT pg_is_in_recovery()'
wait_replay "$(sql primary -Atqc 'SELECT pg_current_wal_flush_lsn()')"
assert_sql primary "SELECT EXISTS (SELECT FROM pg_stat_replication WHERE application_name='lab04_replica' AND state='streaming' AND sync_state='async')"
assert_sql primary "SELECT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name='lab04_replica' AND slot_type='physical' AND active AND wal_status <> 'lost')"
assert_sql replica "SELECT EXISTS (SELECT FROM pg_stat_wal_receiver WHERE status='streaming' AND slot_name='lab04_replica')"
for service in primary replica; do
  sql "$service" < "$LAB_DIR/scripts/validate_database.sql"
done
primary_fingerprint=$(sql primary -At < "$LAB_DIR/scripts/orders_fingerprint.sql")
replica_fingerprint=$(sql replica -At < "$LAB_DIR/scripts/orders_fingerprint.sql")
[[ "$primary_fingerprint" == "$replica_fingerprint" ]] || { echo 'error: fingerprints divergem.' >&2; exit 1; }
token="check-$(date +%s%N)-$$"
probe "$token"
# Verifica o SQLSTATE específico de transação read-only e reverte se escrita for aceita.
output=$(sql replica 2>&1 <<'SQL' || true
\set VERBOSITY verbose
BEGIN;
INSERT INTO audit.replication_probe(token) VALUES ('must-not-write-on-replica');
ROLLBACK;
SQL
)
[[ "$output" == *25006* ]] || { echo "error: réplica não retornou read_only_sql_transaction: $output" >&2; exit 1; }
sql primary -v token="$token" <<'SQL'
DELETE FROM audit.replication_probe WHERE token = :'token';
SQL
echo 'ok: primary, réplica read-only, slot, streaming, dados e propagação validados.'
