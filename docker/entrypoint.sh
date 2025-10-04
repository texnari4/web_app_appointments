#!/bin/sh
set -e
# If you want migrations on start, uncomment the next line (requires prisma CLI present in node_modules)
# npx prisma migrate deploy
exec node dist/index.js
