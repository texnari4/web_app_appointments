#!/bin/sh
set -e
echo "Starting web-app-appointments…"
echo "Node: $(node -v)"
echo "PWD:  $(pwd)"
exec node dist/index.js
