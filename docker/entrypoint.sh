#!/usr/bin/env bash
set -e

export DATA_DIR="${DATA_DIR:-/app/data}"
mkdir -p "$DATA_DIR"

# ensure file exists
if [ ! -f "$DATA_DIR/db.json" ]; then
  echo '{ "masters": [] }' > "$DATA_DIR/db.json"
fi

# relax permissions for Railway volume
chmod -R 777 "$DATA_DIR" || true
chmod 666 "$DATA_DIR/db.json" || true

echo "[entrypoint] DATA_DIR=$DATA_DIR"
node dist/index.js
