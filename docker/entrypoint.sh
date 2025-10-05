#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] Node $(node -v) / npm $(npm -v)"

# ensure db.json exists and is writable
mkdir -p /app/data
DB_FILE="/app/data/db.json"
if [ ! -f "$DB_FILE" ]; then
  echo '{"masters":[],"version":"2.4.4"}' > "$DB_FILE"
fi

# start app
echo "[entrypoint] starting app"
exec node dist/index.js
