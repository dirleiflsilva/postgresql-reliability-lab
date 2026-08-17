#!/usr/bin/env bash
# Executado pelo docker-entrypoint apenas na primeira inicialização do volume.
set -euo pipefail

: "${POSTGRES_USER:?POSTGRES_USER não definido}"
: "${POSTGRES_DB:?POSTGRES_DB não definido}"
: "${BACKUP_USER_PASSWORD:?BACKUP_USER_PASSWORD não definido}"

if [[ "${BACKUP_USER:-backup_user}" != "backup_user" ]]; then
  echo "error: este lab espera BACKUP_USER=backup_user." >&2
  exit 1
fi

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<'SQL'
\getenv backup_user_password BACKUP_USER_PASSWORD

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner') THEN
        CREATE ROLE app_owner NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'app_user_password';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'readonly') THEN
        CREATE ROLE readonly LOGIN PASSWORD 'readonly_password';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'backup_user') THEN
        CREATE ROLE backup_user LOGIN REPLICATION;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'monitor_user') THEN
        CREATE ROLE monitor_user LOGIN PASSWORD 'monitor_password';
    END IF;
END
$$;

ALTER ROLE backup_user PASSWORD :'backup_user_password';

GRANT app_owner TO app_user;
GRANT pg_monitor TO monitor_user;
SQL
