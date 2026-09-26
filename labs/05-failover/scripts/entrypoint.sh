#!/usr/bin/env bash
set -euo pipefail
mkdir -p /var/lib/postgresql/data/pgdata
chown postgres:postgres /var/lib/postgresql/data /var/lib/postgresql/data/pgdata
chmod 700 /var/lib/postgresql/data/pgdata
exec gosu postgres "$@"
