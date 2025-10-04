#!/usr/bin/env sh
set -e

echo "Running Prisma generate..."
npx prisma generate

echo "Trying Prisma migrate deploy..."
if ! npx prisma migrate deploy; then
  echo "migrate deploy failed or no migrations found, falling back to prisma db push..."
  npx prisma db push
fi

echo "Starting app: $*"
exec "$@"
