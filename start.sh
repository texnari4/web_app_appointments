#!/bin/bash
set -e
echo ">>> Развёртывание мини-приложения (сервер + админка)..."

# --- Создание структуры ---
mkdir -p app/public app/data

# --- Тестовые данные ---
cat <<EOF > app/data/services.json
{
  "groups": [
    { "id": 1, "name": "Ногтевой сервис" },
    { "id": 2, "name": "Парикмахерские услуги" },
    { "id": 3, "name": "Массаж" }
  ],
  "services": [
    { "id": 1, "groupId": 1, "name": "Маникюр классический", "description": "Уход за ногтями и кутикулой", "price": 1200, "duration": 60 },
    { "id": 2, "groupId": 1, "name": "Покрытие гель-лаком", "description": "Покрытие ногтей стойким гель-лаком", "price": 1500, "duration": 90 },
    { "id": 3, "groupId": 2, "name": "Стрижка женская", "description": "Модельная стрижка с укладкой", "price": 1800, "duration": 60 },
    { "id": 4, "groupId": 3, "name": "Классический массаж спины", "description": "Расслабляющий массаж", "price": 2000, "duration": 60 }
  ]
}
EOF

# --- Простая админка ---
cat <<'EOF' > app/public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>Админка — BeautyApp</title>
<style>
body { font-family: sans-serif; background: #fafafa; margin: 0; padding: 20px; color: #333; }
h1 { text-align: center; }
.container { max-width: 900px; margin: auto; background: #fff; padding: 20px; border-radius: 12px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
button { padding: 8px 12px; border: none; background: #007bff; color: #fff; border-radius: 6px; cursor: pointer; }
button:hover { background: #0056b3; }
.service { border-bottom: 1px solid #eee; padding: 10px 0; }
label { display:block; margin-top:8px; }
input, textarea, select { width:100%; padding:6px; margin-top:4px; border:1px solid #ccc; border-radius:6px; }
</style>
</head>
<body>
<h1>Управление услугами</h1>
<div class="container">
  <div id="groups"></div>
</div>

<script>
async function loadServices() {
  const data = await fetch('/api/services').then(r => r.json());
  const groups = await fetch('/api/groups').then(r => r.json());
  const container = document.getElementById('groups');
  container.innerHTML = '';
  groups.forEach(g => {
    const div = document.createElement('div');
    div.innerHTML = \`<h2>\${g.name}</h2>\`;
    data.filter(s => s.groupId === g.id).forEach(s => {
      div.innerHTML += \`
        <div class="service">
          <b>\${s.name}</b> — \${s.price}₽ (\${s.duration} мин)
          <p>\${s.description}</p>
        </div>\`;
    });
    container.appendChild(div);
  });
}
loadServices();
</script>
</body>
</html>
EOF

# --- Сервер ---
cat <<'EOF' > app/server.js
import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = process.env.PORT || 8080;
const dataFile = path.join(__dirname, 'data/services.json');

function readData() {
  return JSON.parse(fs.readFileSync(dataFile, 'utf-8'));
}

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, {'Content-Type':'application/json'});
    return res.end(JSON.stringify({ ok:true }));
  }

  if (req.url === '/api/services') {
    res.writeHead(200, {'Content-Type':'application/json'});
    return res.end(JSON.stringify(readData().services));
  }

  if (req.url === '/api/groups') {
    res.writeHead(200, {'Content-Type':'application/json'});
    return res.end(JSON.stringify(readData().groups));
  }

  // --- статика ---
  let filePath = path.join(__dirname, 'public', req.url === '/' ? 'admin.html' : req.url);
  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(404, {'Content-Type':'text/plain'});
      res.end('Файл не найден');
    } else {
      res.writeHead(200, {'Content-Type': filePath.endsWith('.html') ? 'text/html' : 'text/plain'});
      res.end(content);
    }
  });
});

server.listen(PORT, () => console.log('✅ Сервер запущен на порту', PORT));
EOF

echo ">>> Установка Node.js окружения..."
apt-get update -y && apt-get install -y nodejs npm

echo ">>> Запуск сервера..."
cd app
node server.js