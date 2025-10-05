#!/bin/bash
set -e

echo ">>> Развёртывание мини-приложения (сервер + админка)..."

# === Подготовка окружения ===
apt-get update -y
apt-get install -y curl gnupg apt-transport-https ca-certificates

if ! command -v node &> /dev/null; then
  echo ">>> Node.js не найден, устанавливаю..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

# === Создание директорий ===
mkdir -p /app/app/data /app/app/public

# === Файл с тестовыми группами ===
cat << 'EOF' > /app/app/data/groups.json
[
  { "id": 1, "name": "Маникюр" },
  { "id": 2, "name": "Педикюр" },
  { "id": 3, "name": "Брови и ресницы" }
]
EOF

# === Файл с тестовыми услугами ===
cat << 'EOF' > /app/app/data/services.json
[
  { "id": 1, "name": "Маникюр классический", "price": 1500, "groupId": 1 },
  { "id": 2, "name": "Покрытие гель-лаком", "price": 1200, "groupId": 1 },
  { "id": 3, "name": "Педикюр", "price": 1800, "groupId": 2 },
  { "id": 4, "name": "Оформление бровей", "price": 1000, "groupId": 3 }
]
EOF

# === Сервер (ES-модуль) ===
cat << 'EOF' > /app/app/server.mjs
import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = process.env.PORT || 8080;
const DATA_DIR = path.join(__dirname, 'data');
const PUBLIC_DIR = path.join(__dirname, 'public');

const readJSON = (file) => JSON.parse(fs.readFileSync(path.join(DATA_DIR, file), 'utf8'));
const writeJSON = (file, data) => fs.writeFileSync(path.join(DATA_DIR, file), JSON.stringify(data, null, 2));

const server = http.createServer((req, res) => {
  const { url, method } = req;

  // Health-check
  if (url === '/health') {
    res.writeHead(200, {'Content-Type': 'text/plain'});
    return res.end('OK');
  }

  // API
  if (url.startsWith('/api/')) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (method === 'OPTIONS') return res.end();

    if (url === '/api/groups' && method === 'GET') {
      const groups = readJSON('groups.json');
      res.writeHead(200, {'Content-Type': 'application/json'});
      return res.end(JSON.stringify(groups));
    }

    if (url === '/api/services' && method === 'GET') {
      const services = readJSON('services.json');
      res.writeHead(200, {'Content-Type': 'application/json'});
      return res.end(JSON.stringify(services));
    }

    if (url === '/api/services' && method === 'POST') {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', () => {
        const services = readJSON('services.json');
        const newService = JSON.parse(body);
        newService.id = Date.now();
        services.push(newService);
        writeJSON('services.json', services);
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify(newService));
      });
      return;
    }

    if (url.startsWith('/api/services/') && method === 'PUT') {
      const id = parseInt(url.split('/').pop());
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', () => {
        const updated = JSON.parse(body);
        const services = readJSON('services.json').map(s => s.id === id ? {...s, ...updated} : s);
        writeJSON('services.json', services);
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({ ok: true }));
      });
      return;
    }

    if (url.startsWith('/api/services/') && method === 'DELETE') {
      const id = parseInt(url.split('/').pop());
      const services = readJSON('services.json').filter(s => s.id !== id);
      writeJSON('services.json', services);
      res.writeHead(200, {'Content-Type': 'application/json'});
      return res.end(JSON.stringify({ ok: true }));
    }
  }

  // Admin page
  if (url === '/' || url.startsWith('/admin')) {
    const html = fs.readFileSync(path.join(PUBLIC_DIR, 'admin.html'));
    res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
    return res.end(html);
  }

  // Static files
  const filePath = path.join(PUBLIC_DIR, url);
  if (fs.existsSync(filePath)) {
    const ext = path.extname(filePath);
    const type = ext === '.js' ? 'text/javascript' : 'text/html';
    res.writeHead(200, {'Content-Type': `${type}; charset=utf-8`});
    return res.end(fs.readFileSync(filePath));
  }

  res.writeHead(404, {'Content-Type': 'text/plain'});
  res.end('Файл не найден');
});

server.listen(PORT, () => console.log(`✅ Сервер запущен на порту ${PORT}`));
EOF

# === Админка ===
cat << 'EOF' > /app/app/public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Админка — Услуги</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #fafafa; }
    h1 { color: #333; }
    table { border-collapse: collapse; width: 100%; margin-top: 20px; }
    th, td { padding: 10px; border-bottom: 1px solid #ddd; text-align: left; }
    tr:hover { background-color: #f1f1f1; }
    button { background: #2b7cff; color: white; border: none; padding: 6px 12px; border-radius: 6px; cursor: pointer; }
    button:hover { background: #1e60d1; }
    #toast {
      visibility: hidden; min-width: 250px; background: #4CAF50; color: white;
      text-align: center; border-radius: 6px; padding: 10px; position: fixed; z-index: 1;
      left: 50%; bottom: 30px; transform: translateX(-50%);
    }
    #toast.show { visibility: visible; animation: fadein 0.5s, fadeout 0.5s 2s; }
    @keyframes fadein { from {bottom: 0; opacity: 0;} to {bottom: 30px; opacity: 1;} }
    @keyframes fadeout { from {bottom: 30px; opacity: 1;} to {bottom: 0; opacity: 0;} }
  </style>
</head>
<body>
  <h1>Редактирование услуг</h1>

  <label>Фильтр по группе:</label>
  <select id="groupFilter"></select>
  <button onclick="addService()">➕ Добавить услугу</button>

  <table id="servicesTable">
    <thead><tr><th>Название</th><th>Цена</th><th>Группа</th><th>Действия</th></tr></thead>
    <tbody></tbody>
  </table>

  <div id="toast">Изменения сохранены</div>

  <script>
    let groups = [];
    let services = [];

    const toast = (msg='Изменения сохранены') => {
      const t = document.getElementById('toast');
      t.textContent = msg; t.className = 'show';
      setTimeout(()=>t.className=t.className.replace('show',''), 2500);
    };

    async function fetchData() {
      groups = await (await fetch('/api/groups')).json();
      services = await (await fetch('/api/services')).json();
      renderGroups();
      renderServices();
    }

    function renderGroups() {
      const filter = document.getElementById('groupFilter');
      filter.innerHTML = '<option value="">Все</option>' +
        groups.map(g=>`<option value="${g.id}">${g.name}</option>`).join('');
      filter.onchange = renderServices;
    }

    function renderServices() {
      const tbody = document.querySelector('#servicesTable tbody');
      const groupId = document.getElementById('groupFilter').value;
      tbody.innerHTML = '';
      services
        .filter(s => !groupId || s.groupId == groupId)
        .forEach(s => {
          const tr = document.createElement('tr');
          tr.innerHTML = \`
            <td contenteditable onblur="updateService(${s.id}, 'name', this.innerText)">${s.name}</td>
            <td contenteditable onblur="updateService(${s.id}, 'price', parseInt(this.innerText)||0)">${s.price}</td>
            <td>
              <select onchange="updateService(${s.id}, 'groupId', parseInt(this.value))">
                \${groups.map(g=>\`<option value="\${g.id}" \${g.id==s.groupId?'selected':''}>\${g.name}</option>\`).join('')}
              </select>
            </td>
            <td><button onclick="deleteService(${s.id})">🗑️</button></td>
          \`;
          tbody.appendChild(tr);
        });
    }

    async function updateService(id, field, value) {
      const updated = {[field]: value};
      await fetch('/api/services/'+id, { method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify(updated) });
      toast();
    }

    async function addService() {
      const newService = { name: 'Новая услуга', price: 0, groupId: groups[0]?.id || 1 };
      const res = await fetch('/api/services', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(newService) });
      services.push(await res.json());
      renderServices();
      toast('Услуга добавлена');
    }

    async function deleteService(id) {
      await fetch('/api/services/'+id, { method:'DELETE' });
      services = services.filter(s => s.id !== id);
      renderServices();
      toast('Услуга удалена');
    }

    fetchData();
  </script>
</body>
</html>
EOF

# === Запуск ===
cd /app/app
node server.mjs