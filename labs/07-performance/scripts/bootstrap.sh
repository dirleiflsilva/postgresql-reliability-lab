#!/usr/bin/env bash
set -euo pipefail
export PGHOST=/var/run/postgresql PGUSER=postgres
psql -X -v ON_ERROR_STOP=1 -d postgres -c 'CREATE DATABASE appdb'
psql -X -v ON_ERROR_STOP=1 -d appdb -f /lab/init/01_database.sql \
  -v app_password="${APP_PASSWORD:?}" -v readonly_password="${READONLY_PASSWORD:?}" \
  -v monitor_password="${MONITOR_PASSWORD:?MONITOR_PASSWORD não definido}"
