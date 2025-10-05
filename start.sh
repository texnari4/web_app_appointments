#!/bin/bash
set -e

echo ">>> Развёртывание мини-приложения (сервер + админка)..."

mkdir -p app/data
mkdir -p app/public

# --- Тестовые данные ---
cat <<EOF > app/data/services.json
[
  {"id": 1, "name": "Стрижка женская", "price": 1200, "group": "Парикмахерские услуги"},
  {"id": 2, "name": "Стрижка мужская", "price": 800, "group": "Парикмахерские услуги"},
  {"id": 3, "name": "Маникюр классический", "price": 1000, "group": "Ногтевой сервис"}
]
EOF

cat <<EOF > app/data/groups.json
[
  {"id": 1, "name": "Парикмахерские услуги"},
  {"id": 2, "name": "Ногтевой сервис"},
  {"id": 3, "name": "Косметология"}
]
EOF

# --- package.json ---
cat <<EOF > app/package.json
{
  "name": "beauty-miniapp",
  "version": "3.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.19.2"
  }
}
EOF

# --- Сервер ---
cat <<'EOF' > app/server.js
import express from "express";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const dataDir = path.join(__dirname, "data");
const servicesFile = path.join(dataDir, "services.json");
const groupsFile = path.join(dataDir, "groups.json");

const readJSON = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const writeJSON = (file, data) => fs.writeFileSync(file, JSON.stringify(data, null, 2));

app.get("/api/services", (req, res) => {
  res.json(readJSON(servicesFile));
});

app.post("/api/services", (req, res) => {
  const services = readJSON(servicesFile);
  const newService = { id: Date.now(), ...req.body };
  services.push(newService);
  writeJSON(servicesFile, services);
  res.json(newService);
});

app.put("/api/services/:id", (req, res) => {
  const services = readJSON(servicesFile);
  const id = parseInt(req.params.id);
  const idx = services.findIndex(s => s.id === id);
  if (idx === -1) return res.status(404).send("Услуга не найдена");
  services[idx] = { ...services[idx], ...req.body };
  writeJSON(servicesFile, services);
  res.json(services[idx]);
});

app.delete("/api/services/:id", (req, res) => {
  const services = readJSON(servicesFile);
  const id = parseInt(req.params.id);
  const updated = services.filter(s => s.id !== id);
  writeJSON(servicesFile, updated);
  res.json({ ok: true });
});

app.get("/api/groups", (req, res) => {
  res.json(readJSON(groupsFile));
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`✅ Сервер запущен на порту ${PORT}`));
EOF

# --- Минималистичная админка ---
cat <<'EOF' > app/public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Админка услуг</title>
<style>
body { font-family: sans-serif; background: #fafafa; color: #333; margin: 2em; }
h1 { text-align: center; color: #444; }
table { width: 100%; border-collapse: collapse; margin-top: 1em; background: white; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
th, td { padding: 10px; border-bottom: 1px solid #ddd; text-align: left; }
input, select { padding: 5px; }
button { padding: 6px 10px; border: none; border-radius: 4px; background: #1976d2; color: white; cursor: pointer; }
button:hover { background: #125aa3; }
.container { max-width: 800px; margin: auto; }
</style>
</head>
<body>
<div class="container">
<h1>Услуги салона</h1>

<div>
  <input id="name" placeholder="Название услуги">
  <input id="price" type="number" placeholder="Цена">
  <select id="group"></select>
  <button onclick="addService()">Добавить</button>
</div>

<table id="services">
  <thead>
    <tr><th>Название</th><th>Группа</th><th>Цена</th><th>Действия</th></tr>
  </thead>
  <tbody></tbody>
</table>
</div>

<script>
async function loadGroups() {
  const groups = await fetch('/api/groups').then(r => r.json());
  const sel = document.getElementById('group');
  groups.forEach(g => {
    const o = document.createElement('option');
    o.value = g.name; o.textContent = g.name;
    sel.appendChild(o);
  });
}
async function loadServices() {
  const data = await fetch('/api/services').then(r => r.json());
  const tbody = document.querySelector('#services tbody');
  tbody.innerHTML = '';
  data.forEach(s => {
    const tr = document.createElement('tr');
    tr.innerHTML = \`
      <td><input value="\${s.name}" onchange="editService(\${s.id}, 'name', this.value)"></td>
      <td><input value="\${s.group}" onchange="editService(\${s.id}, 'group', this.value)"></td>
      <td><input type='number' value="\${s.price}" onchange="editService(\${s.id}, 'price', this.value)"></td>
      <td><button onclick="delService(\${s.id})">Удалить</button></td>\`;
    tbody.appendChild(tr);
  });
}
async function addService() {
  const name = nameEl.value;
  const price = parseFloat(priceEl.value);
  const group = groupEl.value;
  if (!name || !price) return alert('Введите название и цену');
  await fetch('/api/services', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({name, price, group})});
  loadServices();
}
async function editService(id, key, value) {
  await fetch('/api/services/'+id, {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify({[key]: value})});
}
async function delService(id) {
  await fetch('/api/services/'+id, {method:'DELETE'});
  loadServices();
}
const nameEl = document.getElementById('name');
const priceEl = document.getElementById('price');
const groupEl = document.getElementById('group');
loadGroups().then(loadServices);
</script>
</body>
</html>
EOF

# --- Проверка Node.js ---
if ! command -v node >/dev/null 2>&1; then
  echo ">>> Node.js не найден, устанавливаю..."
  apt-get update -y && apt-get install -y curl
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

cd app
npm install
node server.js