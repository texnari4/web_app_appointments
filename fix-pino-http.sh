#!/bin/bash
set -e

echo "==> Fixing pino-http import (TypeScript ESM + NodeNext)"

INDEX_FILE="./src/index.ts"

if [ ! -f "$INDEX_FILE" ]; then
  echo "❌ File $INDEX_FILE not found!"
  exit 1
fi

# Удаляем старые импорты pino-http
grep -q "pino-http" "$INDEX_FILE" && sed -i.bak '/pino-http/d' "$INDEX_FILE" || true

# Добавляем корректный require в начало
TMP_FILE=$(mktemp)
echo 'import express from "express";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const pinoHttp = require("pino-http");
import pino from "pino";
const logger = pino();
' > "$TMP_FILE"

# Добавляем остальную часть файла
cat "$INDEX_FILE" >> "$TMP_FILE"
mv "$TMP_FILE" "$INDEX_FILE"

echo "✅ Patched pino-http import in $INDEX_FILE"

# Проверим tsconfig.json
if [ -f tsconfig.json ]; then
  echo "==> Ensuring tsconfig.json is NodeNext-compatible"
  cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "esModuleInterop": true,
    "skipLibCheck": true,
    "strict": false,
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
EOF
  echo "✅ tsconfig.json reset for NodeNext"
fi

echo "==> Installing deps and rebuilding..."
npm install
npm run build || {
  echo "❌ Build failed. Check TypeScript output above."
  exit 1
}

echo "🎉 Done! dist/ should now exist and pino-http is fixed."