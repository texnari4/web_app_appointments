#!/bin/bash
set -e

echo ">>> Развёртывание мини-приложения (сервер + админка)..."

APP_DIR="/app"
mkdir -p "$APP_DIR/public" "$APP_DIR/data"

echo ">>> Проверка Node.js..."
if ! command -v node >/dev/null 2>&1; then
  echo ">>> Node.js не найден, устанавливаю..."
  apt-get update -y
  apt-get install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y nodejs
fi

echo ">>> Создаю тестовые данные..."
cat <<EOF > "$APP_DIR/data/services.json"
[
  { "id": 1, "name": "Стрижка", "price": 1200 },
  { "id": 2, "name": "Маникюр", "price": 1500 },
  { "id": 3, "name": "Окрашивание", "price": 2500 }
]
EOF

echo ">>> Создаю админку..."
cat <<'EOF' > "$APP_DIR/public/admin.html"
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Редактирование услуг</title>
  <style>
    body { font-family: sans-serif; padding: 30px; background: #fafafa; color: #333; }
    h1 { text-align: center; }
    table { width: 100%; border-collapse: collapse; margin-top: 20px; background: white; }
    th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
    th { background: #f0f0f0; }
    tr:hover { background: #f9f9f9; }
    button { padding: 6px 12px; border: none; cursor: pointer; border-radius: 5px; }
    .add { background: #4CAF50; color: white; margin-top: 15px; }
    .delete { background: #e74c3c; color: white; }
    .banner { position: fixed; top: 10px; right: 10px; background: #4CAF50; color: white;
              padding: 10px 20px; border-radius: 5px; display: none; animation: fadeout 3s forwards; }
    @keyframes fadeout { 0% {opacity: 1;} 80% {opacity: 1;} 100% {opacity: 0; display:none;} }
  </style>
</head>
<body>
  <h1>Редактирование услуг</h1>
  <table id="servicesTable">
    <thead>
      <tr><th>Название</th><th>Цена (₽)</th><th>Действия</th></tr>
    </thead>
    <tbody></tbody>
  </table>
  <button class="add" onclick="addService()">➕ Добавить услугу</button>

  <div id="banner" class="banner"></div>

  <script>
    const tableBody = document.querySelector('#servicesTable tbody');
    const banner = document.getElementById('banner');

    function showBanner(msg) {
      banner.textContent = msg;
      banner.style.display = 'block';
      setTimeout(() => banner.style.display = 'none', 2500);
    }

    async function fetchServices() {
      const res = await fetch('/api/services');
      const data = await res.json();
      tableBody.innerHTML = '';
      data.forEach(s => {
        const row = document.createElement('tr');
        row.innerHTML = `
          <td contenteditable="true" onblur="updateField(${s.id}, 'name', this.textContent)">${s.name}</td>
          <td contenteditable="true" onblur="updateField(${s.id}, 'price', this.textContent)">${s.price}</td>
          <td><button class="delete" onclick="deleteService(${s.id})">Удалить</button></td>
        `;
        tableBody.appendChild(row);
      });
    }

    async function updateField(id, field, value) {
      await fetch(\`/api/services/\${id}\`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [field]: value })
      });
      showBanner('✅ Изменения сохранены');
    }

    async function deleteService(id) {
      await fetch(\`/api/services/\${id}\`, { method: 'DELETE' });
      showBanner('🗑️ Услуга удалена');
      fetchServices();
    }

    async function addService() {
      await fetch('/api/services', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: 'Новая услуга', price: 0 })
      });
      showBanner('✨ Услуга добавлена');
      fetchServices();
    }

    fetchServices();
  </script>
</body>
</html>
EOF

echo ">>> Создаю сервер..."
cat <<'EOF' > "$APP_DIR/app/server.mjs"
import http from 'http';
import fs from 'fs';
import path from 'path';
import url from 'url';

const PORT = process.env.PORT || 8080;
const DATA_FILE = './app/data/services.json';
const PUBLIC_DIR = './app/public';

function sendJSON(res, data, code = 200) {
  res.writeHead(code, {'Content-Type': 'application/json'});
  res.end(JSON.stringify(data));
}

function readData() {
  if (!fs.existsSync(DATA_FILE)) return [];
  return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
}

function writeData(data) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
}

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);

  if (req.method === 'GET' && parsed.pathname === '/api/services') {
    return sendJSON(res, readData());
  }

  if (req.method === 'POST' && parsed.pathname === '/api/services') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      const data = readData();
      const obj = JSON.parse(body);
      const newItem = { id: Date.now(), name: obj.name || '', price: +obj.price || 0 };
      data.push(newItem);
      writeData(data);
      sendJSON(res, newItem, 201);
    });
    return;
  }

  if (req.method === 'PUT' && parsed.pathname.startsWith('/api/services/')) {
    const id = +parsed.pathname.split('/').pop();
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      const data = readData();
      const idx = data.findIndex(i => i.id === id);
      if (idx === -1) return sendJSON(res, { error: 'Not found' }, 404);
      Object.assign(data[idx], JSON.parse(body));
      writeData(data);
      sendJSON(res, data[idx]);
    });
    return;
  }

  if (req.method === 'DELETE' && parsed.pathname.startsWith('/api/services/')) {
    const id = +parsed.pathname.split('/').pop();
    const data = readData().filter(i => i.id !== id);
    writeData(data);
    return sendJSON(res, { ok: true });
  }

  if (parsed.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('OK');
  }

  const filePath = path.join(PUBLIC_DIR, parsed.pathname === '/' ? 'admin.html' : parsed.pathname);
  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(404, {'Content-Type': 'text/plain; charset=utf-8'});
      res.end('Файл не найден');
    } else {
      res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
      res.end(content);
    }
  });
});

server.listen(PORT, () => console.log(`✅ Сервер запущен на порту ${PORT}`));
EOF

echo ">>> Установка npm-зависимостей (если нужно)..."
cd "$APP_DIR"
npm init -y >/dev/null 2>&1 || true

echo ">>> Запуск приложения..."
node app/server.mjs