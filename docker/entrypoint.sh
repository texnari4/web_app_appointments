#!/usr/bin/env sh
set -e
echo "Starting app with DATA_DIR=${DATA_DIR:-/app/data}"
mkdir -p "${DATA_DIR:-/app/data}"
node dist/index.js
