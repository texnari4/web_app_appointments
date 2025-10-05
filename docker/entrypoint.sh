
#!/bin/sh
set -e

DATA_DIR="${DATA_DIR:-/app/data}"
DB_FILE="${DB_FILE:-$DATA_DIR/db.json}"

mkdir -p "$DATA_DIR"
# try to ensure permissions, ignore errors
chmod 777 "$DATA_DIR" || true

if [ ! -f "$DB_FILE" ]; then
  echo '{"version":"1","masters":[]}' > "$DB_FILE" || true
  chmod 666 "$DB_FILE" || true
fi

exec node dist/index.js
