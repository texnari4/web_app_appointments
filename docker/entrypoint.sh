#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] Node $(node -v) / npm $(npm -v)"
echo "[entrypoint] applying Prisma migrations (safe)"
npx prisma migrate deploy

echo "[entrypoint] starting app"
exec node dist/index.js
