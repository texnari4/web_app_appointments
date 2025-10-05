#!/usr/bin/env sh
set -e
echo "Starting app with DATA_DIR=${DATA_DIR:-/app/data}"
mkdir -p "${DATA_DIR:-/app/data}" || true
node dist/index.js
