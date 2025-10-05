#!/bin/sh
set -e
echo "Starting app with DATA_DIR=${DATA_DIR:-/data}"
mkdir -p "${DATA_DIR:-/data}" || true
node dist/index.js
