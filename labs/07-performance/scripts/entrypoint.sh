#!/usr/bin/env bash
set -euo pipefail
mkdir -p /var/lib/postgresql/data/pgdata /var/log/postgresql
chown postgres:postgres /var/lib/postgresql/data /var/lib/postgresql/data/pgdata /var/log/postgresql
chmod 700 /var/lib/postgresql/data/pgdata
exec gosu postgres "$@"
