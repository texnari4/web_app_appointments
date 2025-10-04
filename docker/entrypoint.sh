
#!/usr/bin/env bash
set -euo pipefail
echo "[entrypoint] DATA_DIR=${DATA_DIR:-/app/data}"
mkdir -p "${DATA_DIR:-/app/data}"
DB="${DATA_DIR:-/app/data}/db.json"
if [ ! -f "$DB" ]; then
  echo '{ "masters": [] }' > "$DB"
  echo "[entrypoint] seeded $DB"
fi
node dist/index.js
