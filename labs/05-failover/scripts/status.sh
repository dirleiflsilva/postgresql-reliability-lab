#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
date -u +%FT%TZ
compose ps -a
compose exec -T client patronictl -c /etc/patroni.yml list
for node in pg1 pg2; do
  echo "--- $node ---"
  sql "$node" -c "SELECT pg_is_in_recovery(), current_setting('transaction_read_only'); SELECT application_name,state,sync_state,replay_lsn FROM pg_stat_replication; SELECT timeline_id FROM pg_control_checkpoint();" || true
done
compose exec -T etcd1 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint status --write-out=table
