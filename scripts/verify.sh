#!/usr/bin/env bash
set -euo pipefail

echo "▶ TypeScript typecheck..."
npm run typecheck

echo "▶ ESLint..."
npm run lint

echo "✔ All checks passed"
