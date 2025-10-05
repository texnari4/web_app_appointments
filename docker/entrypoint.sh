
#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=8080}"
: "${DATA_DIR:=/app/data}"
: "${DB_FILE:=${DATA_DIR}/db.json}"

echo "[entrypoint] Node $(node -v)"
echo "[entrypoint] DATA_DIR=${DATA_DIR} DB_FILE=${DB_FILE}"

mkdir -p "${DATA_DIR}"
# Права достаточно открыть для записи владельцу/группе
chmod 775 "${DATA_DIR}" || true

if [ ! -f "${DB_FILE}" ]; then
  echo "[]" > "${DB_FILE}"
  chmod 664 "${DB_FILE}" || true
fi

exec node dist/index.js
