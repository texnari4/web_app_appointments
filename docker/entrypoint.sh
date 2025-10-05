#!/usr/bin/env bash
set -e
: "${DATA_DIR:=/app/data}"
mkdir -p "$DATA_DIR"
chmod 775 "$DATA_DIR" || true
echo "Starting app with DATA_DIR=$DATA_DIR"
exec node dist/index.js
