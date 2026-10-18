#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

mkdir -p "$LAB_DIR/evidence"
evidence="$LAB_DIR/evidence/$(date -u +%Y%m%dT%H%M%SZ)_observability.txt"
exec > >(tee "$evidence") 2>&1

prom_query() {
  http --get --data-urlencode "query=$1" http://prometheus:9090/api/v1/query
}
grafana_dashboard() {
  compose exec -T client sh -c 'curl -fsS --max-time 10 -u "admin:$GRAFANA_ADMIN_PASSWORD" http://grafana:3000/api/dashboards/uid/postgresql-reliability-overview'
}
two_exporters_up() { prom_query 'count(pg_up == 1)' | grep -Eq '"value":\[[^]]+,"2"\]'; }
one_patroni_leader() { prom_query 'sum(patroni_primary)' | grep -Eq '"value":\[[^]]+,"1"\]'; }
loki_ready() { http http://loki:3100/ready | grep -q ready; }
grafana_ready() { http http://grafana:3000/api/health | grep -Eq '"database"[[:space:]]*:[[:space:]]*"ok"'; }
dashboard_ready() { grafana_dashboard | grep -q 'postgresql-reliability-overview'; }

echo "validation_started_utc=$(date -u +%FT%TZ)"
[[ "$(sql -Atqc 'SELECT count(*) FROM app.customers')" == 100 ]]
[[ "$(sql -Atqc 'SELECT count(*) FROM app.orders')" == 500 ]]
[[ "$(sql -Atqc 'SELECT NOT pg_is_in_recovery()')" == t ]]
[[ "$(sql -Atqc "SELECT count(*) = 1 FROM pg_stat_replication WHERE state='streaming'")" == t ]]
echo 'ok: banco, dados e streaming replication'

wait_until 'dois exporters no Prometheus' two_exporters_up
wait_until 'um líder Patroni no Prometheus' one_patroni_leader
rules="$(http http://prometheus:9090/api/v1/rules)"
[[ "$rules" == *PostgreSQLExporterDown* && "$rules" == *PatroniLeaderMissing* && "$rules" == *ReplicationLagHigh* ]]
echo 'ok: métricas PostgreSQL/Patroni e regras de alerta'

wait_until 'Loki pronto' loki_ready
wait_until 'Grafana pronto' grafana_ready
wait_until 'dashboard provisionado' dashboard_ready
echo 'ok: Loki, Grafana, datasources e dashboard provisionado'

token="observability_check_$(date +%s)_$RANDOM"
sql -c "SELECT pg_sleep(0.35) /* $token */;" >/dev/null
loki_has_token() {
  http --get --data-urlencode 'query={job="postgresql"}' --data-urlencode "limit=100" \
    http://loki:3100/loki/api/v1/query_range | grep -q "$token"
}
wait_until 'log PostgreSQL no Loki' loki_has_token
echo "ok: log PostgreSQL ingerido no Loki; token=$token"
echo "validation_finished_utc=$(date -u +%FT%TZ)"
echo "evidence=$evidence"
