#!/bin/sh
set -e

# Migrate (no-op if none), generate client (safe), then start
npx prisma migrate deploy || true
npx prisma generate || true

exec node dist/index.js
