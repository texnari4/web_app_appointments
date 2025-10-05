#!/usr/bin/env bash
set -e
: "${DATA_DIR:=/app/data}"
mkdir -p "$DATA_DIR"
# fix perms (Railway volume can mount as root)
chmod -R 777 "$DATA_DIR" || true
node dist/index.js
