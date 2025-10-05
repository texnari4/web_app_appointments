#!/bin/bash
echo ">>> Развёртывание мини-приложения (сервер + админка)..."

# Создаём структуру каталогов
mkdir -p app/{data,public}

# ==== data/services.json ====
cat <<'EOF' > app/data/services.json
[
  {
    "id": 1,
    "name": "Маникюр классический",
    "group": "Ногтевой сервис",
    "price": 1500,
    "duration": 60
  },
  {
    "id": 2,
    "name": "Педикюр SPA",
    "group": "Ногтевой сервис",
    "price": 2500,
    "duration": 90
  },
  {
    "id": 3,
    "name": "Окрашивание волос",
    "group": "Парикмахерские услуги",
    "price": 3500,
    "duration": 120
  }
]
EOF

# ==== public/admin.html ====
cat <<'EOF' > app/public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Админка — Beauty Admin</title>
  <style>
    body { font-family: system-ui; background: #f8f8f8; margin: 0; padding: 20px; }
    h1 { color: #333; }
    table { width: 100%; border-collapse: collapse; margin-top: 20px; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background: #fafafa; }
    button { margin: 2px; padding: 6px 10px; cursor: pointer; }
    #form-container { margin-top: 30px; background: white; padding: 15px; border-radius: 6px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    input, select { margin: 5px 0; padding: 6px; width: 100%; }
  </style>
</head>
<body>
  <h1>Админка услуг</h1>
  <table id="services">
    <thead>
      <tr><th>ID</th><th>Название</th><th>Группа</th><th>Цена</th><th>Длительность (мин)</th><th>Действия</th></tr>
    </thead>
    <tbody></tbody>
  </table>

  <div id="form-container">
    <h2 id="form-title">Добавить услугу</h2>
    <form id="service-form">
      <input type="hidden" id="id">
      <label>Название: <input type="text" id="name" required></label><br>
      <label>Группа: <input type="text" id="group" required></label><br>
      <label>Цена (₽): <input type="number" id="price" required></label><br>
      <label>Длительность (мин): <input type="number" id="duration" required></label><br>
      <button type="submit">Сохранить</button>
      <button type="button" id="cancel">Отмена</button>
    </form>
  </div>

  <script>
    async function loadServices() {
      const res = await fetch('/api/services');
      const data = await res.json();
      const tbody = document.querySelector('#services tbody');
      tbody.innerHTML = '';
      data.forEach(s => {
        tbody.innerHTML += \`
          <tr>
            <td>\${s.id}</td>
            <td>\${s.name}</td>
            <td>\${s.group}</td>
            <td>\${s.price}</td>
            <td>\${s.duration}</td>
            <td>
              <button onclick="editService(\${s.id})">✏️</button>
              <button onclick="deleteService(\${s.id})">🗑️</button>
            </td>
          </tr>
        \`;
      });
    }

    async function editService(id) {
      const res = await fetch('/api/services/' + id);
      const s = await res.json();
      document.getElementById('id').value = s.id;
      document.getElementById('name').value = s.name;
      document.getElementById('group').value = s.group;
      document.getElementById('price').value = s.price;
      document.getElementById('duration').value = s.duration;
      document.getElementById('form-title').innerText = 'Редактировать услугу';
    }

    async function deleteService(id) {
      await fetch('/api/services/' + id, { method: 'DELETE' });
      loadServices();
    }

    document.getElementById('service-form').onsubmit = async e => {
      e.preventDefault();
      const body = {
        id: document.getElementById('id').value || undefined,
        name: document.getElementById('name').value,
        group: document.getElementById('group').value,
        price: +document.getElementById('price').value,
        duration: +document.getElementById('duration').value
      };
      await fetch('/api/services', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      e.target.reset();
      document.getElementById('form-title').innerText = 'Добавить услугу';
      loadServices();
    };

    document.getElementById('cancel').onclick = e => {
      document.getElementById('service-form').reset();
      document.getElementById('form-title').innerText = 'Добавить услугу';
    };

    loadServices();
  </script>
</body>
</html>
EOF

# ==== server.mjs ====
cat <<'EOF' > app/server.mjs
import { readFileSync, writeFileSync, existsSync } from 'fs';
import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 8080;
const dataFile = path.join(__dirname, 'data', 'services.json');

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

function loadServices() {
  if (!existsSync(dataFile)) return [];
  return JSON.parse(readFileSync(dataFile, 'utf-8'));
}

function saveServices(data) {
  writeFileSync(dataFile, JSON.stringify(data, null, 2), 'utf-8');
}

app.get('/api/services', (req, res) => {
  res.json(loadServices());
});

app.get('/api/services/:id', (req, res) => {
  const id = parseInt(req.params.id);
  const item = loadServices().find(s => s.id === id);
  res.json(item || {});
});

app.post('/api/services', (req, res) => {
  let data = loadServices();
  const body = req.body;
  if (body.id) {
    const idx = data.findIndex(s => s.id == body.id);
    data[idx] = body;
  } else {
    body.id = Date.now();
    data.push(body);
  }
  saveServices(data);
  res.json({ success: true });
});

app.delete('/api/services/:id', (req, res) => {
  const id = parseInt(req.params.id);
  let data = loadServices().filter(s => s.id !== id);
  saveServices(data);
  res.json({ success: true });
});

app.get('/health', (_, res) => res.send('OK'));

app.listen(PORT, () => console.log(`✅ Сервер запущен на порту ${PORT}`));
EOF

# ==== package.json ====
cat <<'EOF' > app/package.json
{
  "type": "module",
  "dependencies": {
    "express": "^4.19.2"
  },
  "scripts": {
    "start": "node server.mjs"
  }
}
EOF

cd app
npm install
node server.mjs