#!/usr/bin/env sh
set -e

echo "[entrypoint] running prisma: migrate deploy"
npx prisma migrate deploy || true

echo "[entrypoint] running prisma: db push"
npx prisma db push

echo "[entrypoint] running prisma: generate"
npx prisma generate

echo "[entrypoint] starting app on port ${PORT:-8080}"
node dist/index.js
