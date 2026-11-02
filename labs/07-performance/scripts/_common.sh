#!/usr/bin/env bash
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$LAB_DIR/.env" ]] || { echo 'Crie .env a partir de .env.example.' >&2; exit 1; }
compose() { docker compose --project-directory "$LAB_DIR" -f "$LAB_DIR/docker-compose.yml" "$@"; }
sql() { compose exec -T client psql -X -v ON_ERROR_STOP=1 "$@"; }
http() { compose exec -T client curl -fsS --max-time 10 "$@"; }
