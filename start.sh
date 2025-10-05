#!/usr/bin/env bash
set -e

echo ">>> 🚀 Развёртывание мини-приложения (сервер + админка)..."

# --- Подготовка окружения ---
mkdir -p app/data
mkdir -p app/public

# --- Тестовые данные ---
cat <<EOF > app/data/services.json
{
  "groups": [
    {
      "id": 1,
      "name": "Ногтевой сервис",
      "services": [
        {"id": 1, "name": "Маникюр", "description": "Классический маникюр", "price": 1200, "duration": 60},
        {"id": 2, "name": "Покрытие гель-лаком", "description": "Цветное покрытие", "price": 800, "duration": 45}
      ]
    },
    {
      "id": 2,
      "name": "Массаж",
      "services": [
        {"id": 1, "name": "Классический массаж", "description": "Расслабляющий массаж спины", "price": 2500, "duration": 90}
      ]
    }
  ]
}
EOF

# --- package.json (ESM) ---
cat <<EOF > app/package.json
{
  "name": "beauty-miniapp",
  "version": "1.0.0",
  "type": "module",
  "main": "server.js",
  "dependencies": {
    "express": "^4.19.2",
    "body-parser": "^1.20.2"
  },
  "scripts": {
    "start": "node server.js"
  }
}
EOF

# --- Сервер ---
cat <<'EOF' > app/server.js
import express from "express";
import bodyParser from "body-parser";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
const PORT = process.env.PORT || 8080;
const DATA_PATH = path.join(__dirname, "data", "services.json");

app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, "public")));

// --- Health-check ---
app.get("/health", (_, res) => res.json({ status: "ok" }));

// --- Получить все услуги ---
app.get("/api/services", (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(DATA_PATH, "utf-8"));
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: "Ошибка чтения данных" });
  }
});

// --- Сохранить услуги ---
app.post("/api/services", (req, res) => {
  try {
    fs.writeFileSync(DATA_PATH, JSON.stringify(req.body, null, 2), "utf-8");
    res.json({ status: "ok" });
  } catch (e) {
    res.status(500).json({ error: "Ошибка записи файла" });
  }
});

// --- Админка ---
app.get("/admin", (_, res) => {
  res.sendFile(path.join(__dirname, "public", "admin.html"));
});

// --- Запуск ---
app.listen(PORT, () => {
  console.log(`✅ Сервер запущен на порту ${PORT}`);
});
EOF

# --- Простой интерфейс админки ---
cat <<'EOF' > app/public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Админка — Beauty MiniApp</title>
  <style>
    body { font-family: Arial, sans-serif; background: #fafafa; color: #333; padding: 20px; }
    h1 { color: #a84aff; }
    .group { background: white; border-radius: 8px; padding: 15px; margin-bottom: 20px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); }
    .service { border-top: 1px solid #eee; padding: 8px 0; }
    button { margin: 4px; padding: 6px 12px; background: #a84aff; color: white; border: none; border-radius: 5px; cursor: pointer; }
    button:hover { background: #922be7; }
  </style>
</head>
<body>
  <h1>Панель управления услугами</h1>
  <div id="content"></div>

  <script>
    async function load() {
      const res = await fetch('/api/services');
      const data = await res.json();
      const div = document.getElementById('content');
      div.innerHTML = '';
      data.groups.forEach(group => {
        const gEl = document.createElement('div');
        gEl.className = 'group';
        gEl.innerHTML = \`<h2>\${group.name}</h2>\`;
        group.services.forEach(s => {
          const sEl = document.createElement('div');
          sEl.className = 'service';
          sEl.textContent = \`\${s.name} — \${s.price}₽ (\${s.duration} мин)\`;
          gEl.appendChild(sEl);
        });
        div.appendChild(gEl);
      });
    }
    load();
  </script>
</body>
</html>
EOF

# --- Установка Node / npm при необходимости ---
if ! command -v node &>/dev/null; then
  echo ">>> Устанавливаю Node.js..."
  apt-get update -y && apt-get install -y nodejs npm
fi

cd app
npm install
echo ">>> Запуск сервера..."
npm start
EOF