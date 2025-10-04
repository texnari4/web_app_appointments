#!/bin/sh
set -e

echo "🔧 Prisma generate (best-effort)"
if ! npx prisma generate; then
  echo "⚠️  prisma generate failed, continuing (possibly no models)"
fi

if [ -n "$DATABASE_URL" ]; then
  echo "🚀 Applying migrations (deploy)"
  if ! npx prisma migrate deploy; then
    echo "ℹ️  No migrations found, trying db push to sync schema"
    npx prisma db push || true
  fi
else
  echo "⚠️  DATABASE_URL is not set; skipping DB sync"
fi

echo "✅ Starting app"
exec node dist/index.js