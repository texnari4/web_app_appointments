#!/bin/sh
set -e

if command -v prisma >/dev/null 2>&1; then
  echo "Running prisma: generate"
  npx prisma generate || true
  if [ -n "$DATABASE_URL" ]; then
    echo "Running prisma: migrate deploy"
    npx prisma migrate deploy || true
    echo "Running prisma: db push"
    npx prisma db push || true
  fi
else
  echo "Prisma CLI not found, skipping prisma steps"
fi

node dist/index.js
