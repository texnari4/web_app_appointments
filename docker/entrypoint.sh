#!/bin/sh -e
# convert possible CRLF (safety)
if command -v sed >/dev/null 2>&1; then
  sed -i 's/\r$//' "$0" || true
fi

echo "[entrypoint] Prisma generate..."
npx prisma generate || true

echo "[entrypoint] Applying migrations (deploy) or pushing schema..."
if ! npx prisma migrate deploy; then
  npx prisma db push || true
fi

echo "[entrypoint] Starting app..."
exec node dist/index.js
