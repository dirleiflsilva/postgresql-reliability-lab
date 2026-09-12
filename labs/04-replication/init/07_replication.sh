#!/usr/bin/env bash
set -euo pipefail
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD não definida}"
psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
\getenv replication_password REPLICATION_PASSWORD
CREATE ROLE replicator LOGIN REPLICATION PASSWORD :'replication_password';
SELECT pg_create_physical_replication_slot('lab04_replica');
CREATE TABLE audit.replication_probe (
    token text PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE audit.replication_probe OWNER TO app_owner;
SQL
# A rede do Compose isola os serviços; autenticação SCRAM também na replicação.
printf '\nhost replication replicator all scram-sha-256\n' >> "$PGDATA/pg_hba.conf"
