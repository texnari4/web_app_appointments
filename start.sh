#!/bin/bash
set -e

apt-get update -y
apt-get install -y curl ca-certificates gnupg

echo ">>> Развёртывание мини-приложения (сервер + админка)..."

mkdir -p app/data app/public

# Тестовые данные
cat <<'EOF' > app/data/services.json
[
  { "id": 1, "name": "Маникюр", "price": 1500 },
  { "id": 2, "name": "Педикюр", "price": 2000 },
  { "id": 3, "name": "Стрижка", "price": 1800 }
]
EOF

# package.json
cat <<'EOF' > app/package.json
{
  "name": "beauty-miniapp",
  "version": "1.0.0",
  "type": "module",
  "scripts": { "start": "node server.js" },
  "dependencies": { "express": "^4.19.2", "body-parser": "^1.20.2", "cors": "^2.8.5" }
}
EOF

# Сервер
cat <<'EOF' > app/server.js
import express from "express";
import bodyParser from "body-parser";
import fs from "fs";
import path from "path";
import cors from "cors";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 8080;

app.use(cors());
app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, "public")));

const dataFile = path.join(__dirname, "data", "services.json");

app.get("/api/services", (req, res) => {
  fs.readFile(dataFile, "utf8", (err, data) => {
    if (err) return res.status(500).json({ error: "Ошибка чтения файла" });
    res.json(JSON.parse(data));
  });
});

app.put("/api/services/:id", (req, res) => {
  const id = parseInt(req.params.id);
  const { name, price } = req.body;
  fs.readFile(dataFile, "utf8", (err, data) => {
    if (err) return res.status(500).json({ error: "Ошибка чтения" });
    let services = JSON.parse(data);
    const index = services.findIndex(s => s.id === id);
    if (index === -1) return res.status(404).json({ error: "Не найдено" });
    services[index] = { ...services[index], name, price };
    fs.writeFile(dataFile, JSON.stringify(services, null, 2), err2 => {
      if (err2) return res.status(500).json({ error: "Ошибка записи" });
      res.json(services[index]);
    });
  });
});

app.post("/api/services", (req, res) => {
  const { name, price } = req.body;
  fs.readFile(dataFile, "utf8", (err, data) => {
    if (err) return res.status(500).json({ error: "Ошибка чтения" });
    const services = JSON.parse(data);
    const newService = { id: Date.now(), name, price };
    services.push(newService);
    fs.writeFile(dataFile, JSON.stringify(services, null, 2), err2 => {
      if (err2) return res.status(500).json({ error: "Ошибка записи" });
      res.json(newService);
    });
  });
});

app.delete("/api/services/:id", (req, res) => {
  const id = parseInt(req.params.id);
  fs.readFile(dataFile, "utf8", (err, data) => {
    if (err) return res.status(500).json({ error: "Ошибка чтения" });
    let services = JSON.parse(data);
    services = services.filter(s => s.id !== id);
    fs.writeFile(dataFile, JSON.stringify(services, null, 2), err2 => {
      if (err2) return res.status(500).json({ error: "Ошибка записи" });
      res.json({ success: true });
    });
  });
});

app.get("/health", (req, res) => res.send("OK"));
app.get("/", (req, res) => res.sendFile(path.join(__dirname, "public", "admin.html")));

app.listen(PORT, () => console.log(`✅ Сервер запущен на порту ${PORT}`));
EOF

# Админ-панель с inline-редактированием
cat <<'EOF' > app/public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Админка услуг</title>
  <style>
    body { font-family: sans-serif; padding: 20px; background: #fafafa; }
    table { border-collapse: collapse; width: 100%; background: white; }
    th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
    td[contenteditable="true"] { background: #fffbe6; }
    .banner { 
      position: fixed; top: 10px; right: 10px; 
      background: #4CAF50; color: white; padding: 10px 15px; border-radius: 6px;
      opacity: 0; transition: opacity 0.3s ease;
    }
    .banner.show { opacity: 1; }
    button { margin: 5px; }
  </style>
</head>
<body>
  <h1>Редактирование услуг</h1>
  <table id="servicesTable">
    <thead><tr><th>Название</th><th>Цена</th><th>Действия</th></tr></thead>
    <tbody></tbody>
  </table>
  <button id="addBtn">➕ Добавить услугу</button>

  <div class="banner" id="banner">Сохранено ✅</div>

  <script>
    async function loadServices() {
      const res = await fetch('/api/services');
      const data = await res.json();
      const tbody = document.querySelector('#servicesTable tbody');
      tbody.innerHTML = '';
      data.forEach(s => {
        const tr = document.createElement('tr');
        tr.innerHTML = \`
          <td contenteditable="true" data-field="name" data-id="\${s.id}">\${s.name}</td>
          <td contenteditable="true" data-field="price" data-id="\${s.id}">\${s.price}</td>
          <td><button data-id="\${s.id}" class="deleteBtn">🗑️</button></td>
        \`;
        tbody.appendChild(tr);
      });
    }

    async function updateService(id, field, value) {
      const row = document.querySelector(\`[data-id="\${id}"][data-field="name"]\`);
      const name = row.textContent.trim();
      const price = document.querySelector(\`[data-id="\${id}"][data-field="price"]\`).textContent.trim();
      await fetch(\`/api/services/\${id}\`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, price })
      });
      showBanner('Изменения сохранены ✅');
    }

    async function deleteService(id) {
      await fetch(\`/api/services/\${id}\`, { method: 'DELETE' });
      showBanner('Услуга удалена ❌');
      loadServices();
    }

    async function addService() {
      await fetch('/api/services', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: 'Новая услуга', price: 0 })
      });
      showBanner('Услуга добавлена ✅');
      loadServices();
    }

    function showBanner(msg) {
      const banner = document.getElementById('banner');
      banner.textContent = msg;
      banner.classList.add('show');
      setTimeout(() => banner.classList.remove('show'), 3000);
    }

    document.addEventListener('focusout', e => {
      if (e.target.hasAttribute('contenteditable')) {
        const id = e.target.dataset.id;
        const field = e.target.dataset.field;
        updateService(id, field, e.target.textContent.trim());
      }
    });

    document.addEventListener('click', e => {
      if (e.target.classList.contains('deleteBtn')) deleteService(e.target.dataset.id);
      if (e.target.id === 'addBtn') addService();
    });

    loadServices();
  </script>
</body>
</html>
EOF

# Установка Node.js если нет
if ! command -v node >/dev/null 2>&1; then
  echo ">>> Node.js не найден, устанавливаю..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

cd app
npm install
npm start
EOF