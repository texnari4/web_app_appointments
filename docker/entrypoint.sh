#!/bin/sh
set -eu

echo "[entrypoint] Node $(node -v) / npm $(npm -v)"
echo "[entrypoint] applying Prisma migrations (safe)"
npx prisma migrate deploy

if [ "${PRISMA_DB_PUSH:-0}" = "1" ]; then
  echo "[entrypoint] PRISMA_DB_PUSH=1 -> running 'prisma db push'"
  if [ "${PRISMA_DB_PUSH_ACCEPT_DATA_LOSS:-0}" = "1" ]; then
    echo "[entrypoint] --accept-data-loss is enabled"
    npx prisma db push --accept-data-loss
  else
    npx prisma db push
  fi
else
  echo "[entrypoint] skipping 'prisma db push' (PRISMA_DB_PUSH is not 1)"
fi

echo "[entrypoint] starting app"
exec node dist/index.js
