#!/usr/bin/env bash
set -euo pipefail
export PGHOST=/var/run/postgresql PGUSER=postgres
# Patroni remove suas variáveis sensíveis antes de executar callbacks.
# O bootstrap usa o socket local dentro do container.
export POSTGRES_USER=postgres POSTGRES_DB=appdb
psql -X -v ON_ERROR_STOP=1 -d postgres -c 'CREATE DATABASE appdb'
for file in /lab/init/*; do
  case "$file" in
    *.sh) bash "$file" ;;
    *.sql) psql -X -v ON_ERROR_STOP=1 -d appdb -f "$file" ;;
  esac
done
