#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

echo '== Containers =='
compose ps
echo
echo '== Cluster Patroni =='
compose exec -T client patronictl -c /etc/patroni.yml list
echo
echo '== Targets Prometheus =='
http http://prometheus:9090/api/v1/targets | grep -o '"health":"[^"]*"' | sort | uniq -c
echo
echo '== Alertas ativos =='
http http://prometheus:9090/api/v1/alerts
