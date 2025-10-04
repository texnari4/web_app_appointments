#!/bin/sh
set -e

# Sync Prisma schema at startup (safe on existing DB)
npx prisma migrate deploy || true
npx prisma db push || true
npx prisma generate || true

exec node dist/index.js
