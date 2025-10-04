
#!/bin/sh
set -e

echo "[entrypoint] Prisma generate (best-effort)"
if npx prisma generate 1>/dev/null; then
  echo "[entrypoint] prisma generate ok"
else
  echo "[entrypoint] prisma generate failed (continuing)"
fi

echo "[entrypoint] prisma migrate deploy || db push"
if npx prisma migrate deploy; then
  echo "[entrypoint] migrate deploy ok"
else
  echo "[entrypoint] migrate deploy failed, trying db push"
  npx prisma db push || true
fi

echo "[entrypoint] start node app"
node dist/index.js
