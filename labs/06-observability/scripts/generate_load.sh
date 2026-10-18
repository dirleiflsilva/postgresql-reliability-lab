#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

duration="${1:-60}"
[[ "$duration" =~ ^[1-9][0-9]*$ ]] || { echo 'uso: generate_load.sh [segundos]' >&2; exit 2; }
deadline=$((SECONDS + duration))
echo "Gerando consultas por ${duration}s..."
while (( SECONDS < deadline )); do
  sql -qAt <<'SQL' >/dev/null
SELECT count(*) FROM app.orders WHERE status = 'paid';
SELECT sum(total_amount) FROM app.orders WHERE ordered_at >= now() - interval '30 days';
SELECT pg_sleep(0.30);
SQL
done
echo 'Carga concluída. Consulte o dashboard e os logs no Grafana.'
