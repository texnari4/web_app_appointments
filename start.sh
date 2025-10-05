#!/bin/bash
set -e
echo ">>> 🚀 Развёртывание мини-приложения (сервер + админка)..."

# === 1. Подготовка окружения ===
APP_DIR="/app"
mkdir -p "$APP_DIR/app" "$APP_DIR/public" "$APP_DIR/data"

cd "$APP_DIR"

echo ">>> Проверка Node.js..."
if ! command -v node >/dev/null 2>&1; then
  echo ">>> Node.js не найден, устанавливаю..."
  apt-get update -y
  apt-get install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y nodejs
fi

if ! command -v npm >/dev/null 2>&1; then
  echo ">>> npm не найден, устанавливаю..."
  apt-get install -y npm
fi

# === 2. Тестовые данные ===
echo ">>> Создаю тестовые данные..."
cat <<EOF > "$APP_DIR/data/services.json"
[
  { "id": 1, "name": "Стрижка", "price": 1000 },
  { "id": 2, "name": "Окрашивание", "price": 2500 },
  { "id": 3, "name": "Маникюр", "price": 1500 }
]
EOF

# === 3. HTML интерфейс (админка) ===
echo ">>> Создаю админку..."
cat <<'EOF' > "$APP_DIR/public/admin.html"
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <title>Редактирование услуг</title>
  <style>
    body { font-family: sans-serif; background: #fafafa; padding: 20px; }
    h1 { text-align: center; }
    table { width: 100%; border-collapse: collapse; margin-top: 20px; background: #fff; }
    th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
    th { background: #f3f3f3; }
    tr:hover { background: #f9f9f9; }
    button { background: #2d8cf0; color: white; border: none; padding: 6px 10px; border-radius: 4px; cursor: pointer; }
    button:hover { background: #1a73e8; }
    #banner { display:none; position:fixed; top:20px; right:20px; background:#4caf50; color:white; padding:10px 20px; border-radius:8px; box-shadow:0 4px 8px rgba(0,0,0,0.2); }
  </style>
</head>
<body>
  <h1>Редактирование услуг</h1>
  <button onclick="addService()">➕ Добавить услугу</button>
  <table id="servicesTable">
    <thead>
      <tr><th>Название</th><th>Цена</th><th>Действия</th></tr>
    </thead>
    <tbody></tbody>
  </table>
  <div id="banner">✅ Изменения сохранены!</div>
<script>
const banner = document.getElementById('banner');
function showBanner(msg='✅ Изменения сохранены!') {
  banner.innerText = msg;
  banner.style.display='block';
  setTimeout(()=>banner.style.display='none',1500);
}
async function loadServices() {
  const res = await fetch('/api/services');
  const data = await res.json();
  const tbody = document.querySelector('#servicesTable tbody');
  tbody.innerHTML = '';
  data.forEach(s => {
    const row = document.createElement('tr');
    row.innerHTML = `
      <td contenteditable="true" onblur="updateField(${s.id}, 'name', this.innerText)">${s.name}</td>
      <td contenteditable="true" onblur="updateField(${s.id}, 'price', this.innerText)">${s.price}</td>
      <td><button onclick="deleteService(${s.id})">🗑 Удалить</button></td>`;
    tbody.appendChild(row);
  });
}
async function updateField(id, field, value) {
  await fetch('/api/services/' + id, {
    method: 'PATCH',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({ [field]: value })
  });
  showBanner();
}
async function addService() {
  const name = prompt('Название новой услуги:');
  const price = prompt('Цена:');
  if (!name || !price) return;
  await fetch('/api/services', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({ name, price: Number(price) })
  });
  showBanner('✅ Услуга добавлена!');
  loadServices();
}
async function deleteService(id) {
  if (!confirm('Удалить услугу?')) return;
  await fetch('/api/services/' + id, { method: 'DELETE' });
  showBanner('🗑 Услуга удалена');
  loadServices();
}
loadServices();
</script>
</body>
</html>
EOF

# === 4. Сервер ===
echo ">>> Создаю сервер..."
cat <<'EOF' > "$APP_DIR/app/server.mjs"
import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 8080;
const DATA_PATH = '/app/data/services.json';
const PUBLIC_DIR = '/app/public';

app.use(express.json());
app.use(express.static(PUBLIC_DIR));

app.get('/health', (req, res) => res.send('OK'));

// === API ===
app.get('/api/services', (req, res) => {
  const data = JSON.parse(fs.readFileSync(DATA_PATH, 'utf-8'));
  res.json(data);
});

app.post('/api/services', (req, res) => {
  const data = JSON.parse(fs.readFileSync(DATA_PATH, 'utf-8'));
  const newId = data.length ? Math.max(...data.map(s => s.id)) + 1 : 1;
  const newService = { id: newId, ...req.body };
  data.push(newService);
  fs.writeFileSync(DATA_PATH, JSON.stringify(data, null, 2));
  res.json(newService);
});

app.patch('/api/services/:id', (req, res) => {
  const id = Number(req.params.id);
  const data = JSON.parse(fs.readFileSync(DATA_PATH, 'utf-8'));
  const idx = data.findIndex(s => s.id === id);
  if (idx === -1) return res.status(404).send('Not found');
  data[idx] = { ...data[idx], ...req.body };
  fs.writeFileSync(DATA_PATH, JSON.stringify(data, null, 2));
  res.json(data[idx]);
});

app.delete('/api/services/:id', (req, res) => {
  const id = Number(req.params.id);
  let data = JSON.parse(fs.readFileSync(DATA_PATH, 'utf-8'));
  data = data.filter(s => s.id !== id);
  fs.writeFileSync(DATA_PATH, JSON.stringify(data, null, 2));
  res.sendStatus(204);
});

app.get('/', (req, res) => res.redirect('/admin.html'));

app.listen(PORT, () => console.log(`✅ Сервер запущен на порту ${PORT}`));
EOF

# === 5. package.json ===
echo ">>> Создаю package.json..."
cat <<EOF > "$APP_DIR/package.json"
{
  "name": "beautyminiappappointments",
  "version": "9.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.19.2"
  },
  "scripts": {
    "start": "node app/server.mjs"
  }
}
EOF

# === 6. Установка зависимостей и запуск ===
echo ">>> Устанавливаю зависимости..."
npm install --silent

echo ">>> Запуск сервера..."
node app/server.mjs
EOF