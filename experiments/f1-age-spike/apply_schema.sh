#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < schema.cypher
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < indexes.sql
