#!/usr/bin/env bash
set -euo pipefail
: "${DATA_DIR:=/app/data}"
mkdir -p "$DATA_DIR"
if [ ! -f "$DATA_DIR/db.json" ]; then
  echo '{"masters":[]}' > "$DATA_DIR/db.json"
fi
echo "[entrypoint] starting app"
exec node dist/index.js
