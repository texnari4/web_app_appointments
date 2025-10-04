#!/bin/sh
set -e

echo "[entrypoint] Node $(node -v) / npm $(npm -v)"
echo "[entrypoint] applying Prisma migrations (safe)"

npx prisma migrate deploy || true
# No destructive push on start; only generate and start
echo "[entrypoint] starting app"
exec node dist/index.js
