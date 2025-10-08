#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> 🚀 Развёртывание мини-приложения (сервер + админка v13)..."

# --- Подготовка директорий ---
# mkdir -p app/data - создаётся автоматически при первом запуске, включить при первом деплое
mkdir -p app/public
mkdir -p app/templates

# --- Проверка Node.js ---
if ! command -v node &>/dev/null; then
  echo ">>> Node.js не найден. Устанавливаю..."
  apt-get update -y
  apt-get install -y curl gnupg
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y nodejs
fi

cd app

# --- package.json ---
cat <<EOF > package.json
{
  "name": "beautyminiappappointments",
  "version": "13.0.0",
  "type": "module",
  "scripts": {
    "start": "node server.mjs"
  }
}
EOF

# --- server.mjs ---
cp "$SCRIPT_DIR/templates/server.mjs" server.mjs


#
# --- client.html ---
cp templates/client.html public/client.html
# --- admin.html ---
# ADMIN UI template will be copied below
cp "$SCRIPT_DIR/templates/admin.html" public/admin.html

echo ">>> Установка зависимостей..."
npm install --omit=dev
npm install adm-zip busboy --omit=dev

echo ">>> Запуск сервера..."
npm start

 # --- admin.html ---
 cp "$SCRIPT_DIR/templates/admin.html" public/admin.html

 
    // ===== CONTACTS API =====
    if (pathname === '/api/contacts/me' && req.method === 'GET') {
      if (!ctx.telegramId) { sendJSON(res, 200, { contact: null }); return; }
      const list = readContacts();
      const c = list.find(x => String(x.id) === String(ctx.telegramId)) || null;
      sendJSON(res, 200, { contact: c });
      return;
    }

    if (pathname === '/api/contacts/bootstrap' && req.method === 'POST') {
      // Upsert from WebApp: we trust cookie set via /auth/telegram; optionally merge name/username in body
      if (!ctx.telegramId) { sendJSON(res, 400, { error: 'not in Telegram WebApp (no tg_id)' }); return; }
      let body = {};
      try { body = JSON.parse(await readBody(req) || '{}'); } catch {}
      const next = {
        id: ctx.telegramId,
        username: (body.username ?? '').replace(/^@/, '') || undefined,
        first_name: body.first_name ?? undefined,
        last_name: body.last_name ?? undefined,
        phone: body.phone ?? undefined
      };
      upsertContact(next);
      sendJSON(res, 200, { ok: true });
      return;
    }
#
# --- manager.html ---
cp templates/managel.html templates/managel.html