#!/usr/bin/env bash
set -euo pipefail

# Prepare data dir and file with permissive rights for mounted volumes
mkdir -p "${DATA_DIR:-/app/data}"
touch "${DATA_DIR:-/app/data}/db.json" || true
chmod -R 777 /app || true
chmod 666 "${DATA_DIR:-/app/data}/db.json" || true

node dist/index.js