#!/usr/bin/env sh
set -e

echo "[entrypoint] Node $(node -v) / npm $(npm -v)"

echo "[entrypoint] applying Prisma migrations (safe)"
npx prisma migrate deploy

if [ "${PRISMA_DB_PUSH}" = "1" ]; then
  echo "[entrypoint] PRISMA_DB_PUSH=1 → running prisma db push"
  if [ "${PRISMA_DB_PUSH_ACCEPT_DATA_LOSS}" = "1" ]; then
    npx prisma db push --accept-data-loss
  else
    npx prisma db push
  fi
fi

echo "[entrypoint] starting app on port ${PORT:-8080}"
exec node dist/index.js
