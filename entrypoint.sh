#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=8080}"
: "${DATA_DIR:=/app/data}"
: "${DB_FILE:=${DATA_DIR}/db.json}"

echo "[entrypoint] DATA_DIR=${DATA_DIR}, DB_FILE=${DB_FILE}"

# 1) Создаём каталог и отдаём права текущему пользователю (root подходит, можно оставить)
mkdir -p "${DATA_DIR}"
chmod 775 "${DATA_DIR}" || true

# 2) Если нужно запускать под user=node, то раскомментируй CHOWN:
# chown -R node:node "${DATA_DIR}" || true

# 3) Инициализируем db.json, если его нет
if [ ! -f "${DB_FILE}" ]; then
  echo '[]' > "${DB_FILE}"
  chmod 664 "${DB_FILE}" || true
fi

echo "[entrypoint] starting app on :${PORT}"
exec node dist/index.js