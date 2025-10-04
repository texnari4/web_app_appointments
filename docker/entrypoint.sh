#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] Node $(node -v) / npm $(npm -v)"
echo "[entrypoint] DATA_DIR=${DATA_DIR:-/app/data}"

# Ensure data dir and seed DB file
mkdir -p "${DATA_DIR:-/app/data}"
if [ ! -f "${DATA_DIR:-/app/data}/db.json" ]; then
  echo '{"meta":{"version":"2.4.0","createdAt":"'"$(date -u +%FT%TZ)"'"},"masters":[],"services":[]}' > "${DATA_DIR:-/app/data}/db.json"
  echo "[entrypoint] seeded ${DATA_DIR:-/app/data}/db.json"
fi

echo "[entrypoint] starting app"
exec node dist/index.js
