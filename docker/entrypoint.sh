#!/usr/bin/env bash
set -e

: "${PORT:=8080}"
: "${DATA_DIR:=/data}"

echo "Starting app with DATA_DIR=${DATA_DIR}"
# Ensure directory exists (may be read-only for perms change; just mkdir -p and ignore failures)
mkdir -p "${DATA_DIR}" || true

exec node dist/index.js