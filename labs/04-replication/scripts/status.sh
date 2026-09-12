#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
compose ps
sql primary -c "SELECT application_name, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_gap_bytes FROM pg_stat_replication"
sql primary -c "SELECT slot_name, active, wal_status, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal FROM pg_replication_slots"
sql replica -c 'SELECT pg_is_in_recovery(), pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()'
