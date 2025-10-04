#!/bin/sh
set -e
echo "[entrypoint] starting server on :${PORT:-8080}"
exec node dist/index.js
