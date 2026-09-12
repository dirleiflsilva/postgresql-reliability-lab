#!/usr/bin/env bash
set -euo pipefail
: "${PGDATA:?}"
: "${REPLICATION_PASSWORD:?}"
if [[ "$(id -u)" == 0 ]]; then
  install -d -m 0700 -o postgres -g postgres "$PGDATA"
  exec gosu postgres bash "$0" "$@"
fi
# O passfile fica fora do volume e é recriado em cada inicialização.
# Escape de ':' e '\' conforme o formato .pgpass.
password=${REPLICATION_PASSWORD//\\/\\\\}
password=${password//:/\\:}
umask 077
printf 'primary:5432:replication:replicator:%s\n' "$password" > /tmp/lab04.pgpass
unset password REPLICATION_PASSWORD
export PGPASSFILE=/tmp/lab04.pgpass
if [[ ! -s "$PGDATA/PG_VERSION" ]]; then
  # O backup incompleto permanece separado do diretório final.
  staging="${PGDATA}.bootstrap"
  mkdir -p "$staging"
  find "$staging" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  pg_basebackup \
    --dbname='host=primary port=5432 user=replicator application_name=lab04_replica passfile=/tmp/lab04.pgpass' \
    --pgdata="$staging" --wal-method=stream --checkpoint=fast \
    --slot=lab04_replica --write-recovery-conf --no-password
  # A troca no mesmo volume publica apenas um backup completo.
  rmdir "$PGDATA"
  mv "$staging" "$PGDATA"
fi
if [[ ! -f "$PGDATA/standby.signal" ]]; then
  echo 'error: volume não está configurado como standby; inicialização recusada.' >&2
  exit 1
fi
exec "$@"
