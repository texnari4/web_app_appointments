#!/bin/bash
set -e

echo ">>> 🚀 Развёртывание мини-приложения (сервер + админка v13)..."

# --- Подготовка директорий ---
mkdir -p app/data
mkdir -p app/public

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
cat <<'EOF' > server.mjs
import { createServer } from 'http';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { parse } from 'url';
import { dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = __dirname + '/data';
mkdirSync(DATA_DIR, { recursive: true });

const servicesFile = DATA_DIR + '/services.json';
const groupsFile = DATA_DIR + '/groups.json';

// --- Создание тестовых данных ---
if (!existsSync(servicesFile) || readFileSync(servicesFile, 'utf-8').trim() === '') {
  const testServices = [
    { id: 1, name: "Массаж спины", price: 1500, group: "Массаж" },
    { id: 2, name: "Стрижка", price: 800, group: "Парикмахер" },
    { id: 3, name: "Маникюр", price: 1200, group: "Ногтевой сервис" }
  ];
  writeFileSync(servicesFile, JSON.stringify(testServices, null, 2));
}

if (!existsSync(groupsFile) || readFileSync(groupsFile, 'utf-8').trim() === '') {
  const testGroups = [
    { id: 1, name: "Массаж" },
    { id: 2, name: "Парикмахер" },
    { id: 3, name: "Ногтевой сервис" }
  ];
  writeFileSync(groupsFile, JSON.stringify(testGroups, null, 2));
}

function readJSON(file) {
  return JSON.parse(readFileSync(file, 'utf-8'));
}
function writeJSON(file, data) {
  writeFileSync(file, JSON.stringify(data, null, 2));
}

const server = createServer((req, res) => {
  const { pathname, query } = parse(req.url, true);

  if (pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('OK');
    return;
  }

  if (pathname === '/api/services' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(readFileSync(servicesFile));
    return;
  }

  if (pathname === '/api/groups' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(readFileSync(groupsFile));
    return;
  }

  if (pathname === '/api/services' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      const service = JSON.parse(body);
      const services = readJSON(servicesFile);
      service.id = Date.now();
      services.push(service);
      writeJSON(servicesFile, services);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true }));
    });
    return;
  }

  if (pathname.startsWith('/api/services/') && req.method === 'PUT') {
    const id = parseInt(pathname.split('/').pop());
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      const update = JSON.parse(body);
      const services = readJSON(servicesFile).map(s => s.id === id ? { ...s, ...update } : s);
      writeJSON(servicesFile, services);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true }));
    });
    return;
  }

  if (pathname.startsWith('/api/services/') && req.method === 'DELETE') {
    const id = parseInt(pathname.split('/').pop());
    const services = readJSON(servicesFile).filter(s => s.id !== id);
    writeJSON(servicesFile, services);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true }));
    return;
  }

  if (pathname === '/' || pathname === '/admin/' || pathname.startsWith('/admin')) {
    const html = readFileSync(__dirname + '/public/admin.html', 'utf-8');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Файл не найден');
});

const PORT = process.env.PORT || 8080;
server.listen(PORT, () => console.log(`✅ Сервер запущен на порту ${PORT}`));
EOF

# --- admin.html ---
cat <<'EOF' > public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>Админка — Управление услугами</title>
<style>
body { font-family: Arial; margin: 40px; background: #fafafa; }
h1 { color: #333; }
table { width: 100%; border-collapse: collapse; margin-top: 20px; }
th, td { padding: 10px; border: 1px solid #ccc; text-align: left; }
th { background: #eee; }
button { cursor: pointer; padding: 6px 12px; border: none; border-radius: 5px; }
button:hover { opacity: 0.8; }
.add-btn { background: #28a745; color: white; margin-top: 10px; }
.del-btn { background: #dc3545; color: white; }
.banner { position: fixed; top: 20px; right: 20px; background: #4caf50; color: white; padding: 12px 18px; border-radius: 6px; display: none; }
</style>
</head>
<body>
<h1>Редактирование услуг</h1>

<label>Фильтр по группе: </label>
<select id="groupFilter"></select>

<table id="servicesTable">
<thead>
<tr><th>Название</th><th>Цена</th><th>Группа</th><th>Действия</th></tr>
</thead>
<tbody></tbody>
</table>

<button class="add-btn" id="addBtn">➕ Добавить услугу</button>
<div class="banner" id="banner">Изменения сохранены</div>

<script>
document.addEventListener('DOMContentLoaded', () => {
  const apiBase = '/api';
  let services = [];
  let groups = [];

  async function loadData() {
    const sResp = await fetch(apiBase + '/services');
    const gResp = await fetch(apiBase + '/groups');
    services = await sResp.json();
    groups = await gResp.json();
    renderGroups();
    renderTable();
  }

  function renderGroups() {
    const filter = document.getElementById('groupFilter');
    let html = '<option value="">Все</option>';
    for (const g of groups) html += '<option value="' + g.name + '">' + g.name + '</option>';
    filter.innerHTML = html;
    filter.onchange = renderTable;
  }

  function renderTable() {
    const tbody = document.querySelector('#servicesTable tbody');
    const groupFilter = document.getElementById('groupFilter').value;
    tbody.innerHTML = '';
    for (const s of services) {
      if (groupFilter && s.group !== groupFilter) continue;
      const tr = document.createElement('tr');
      tr.innerHTML =
        '<td contenteditable="true" onblur="updateService(' + s.id + ', \\'name\\', this.innerText)">' + s.name + '</td>' +
        '<td contenteditable="true" onblur="updateService(' + s.id + ', \\'price\\', this.innerText)">' + s.price + '</td>' +
        '<td contenteditable="true" onblur="updateService(' + s.id + ', \\'group\\', this.innerText)">' + s.group + '</td>' +
        '<td><button class="del-btn" onclick="deleteService(' + s.id + ')">Удалить</button></td>';
      tbody.appendChild(tr);
    }
  }

  window.addService = async function () {
    const newService = { name: "Новая услуга", price: 0, group: groups[0]?.name || "" };
    await fetch(apiBase + '/services', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(newService)
    });
    showBanner("Услуга добавлена");
    await loadData();
  }

  window.updateService = async function (id, field, value) {
    await fetch(apiBase + '/services/' + id, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ [field]: value })
    });
    showBanner("Изменения сохранены");
  }

  window.deleteService = async function (id) {
    await fetch(apiBase + '/services/' + id, { method: 'DELETE' });
    showBanner("Услуга удалена");
    await loadData();
  }

  function showBanner(text) {
    const banner = document.getElementById('banner');
    banner.textContent = text;
    banner.style.display = 'block';
    setTimeout(() => banner.style.display = 'none', 2000);
  }

  document.getElementById('addBtn').onclick = addService;
  loadData();
});
</script>
</body>
</html>
EOF

echo ">>> Установка зависимостей..."
npm install --omit=dev

echo ">>> Запуск сервера..."
npm start