#!/bin/bash
set -e
echo ">>> Setting up full project (server + admin)..."

mkdir -p data public

# --- package.json ---
cat <<'EOF' > package.json
{
  "name": "beautyminiappappointments",
  "version": "5.0.0",
  "type": "module",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.21.2"
  }
}
EOF

# --- server.js ---
cat <<'EOF' > server.js
import express from "express";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const dataPath = path.join(__dirname, "data/services.json");

// Load JSON data
function loadData() {
  try {
    return JSON.parse(fs.readFileSync(dataPath, "utf8"));
  } catch (err) {
    console.error("Error loading data:", err);
    return { groups: [] };
  }
}

// Save JSON data
function saveData(data) {
  fs.writeFileSync(dataPath, JSON.stringify(data, null, 2), "utf8");
}

// --- API ---
app.get("/api/groups", (req, res) => {
  const data = loadData();
  res.json(data.groups);
});

app.get("/api/services", (req, res) => {
  const data = loadData();
  const allServices = data.groups.flatMap(g => g.services.map(s => ({ ...s, group: g.name })));
  res.json(allServices);
});

app.post("/api/groups", (req, res) => {
  const data = loadData();
  data.groups.push({ name: req.body.name, services: [] });
  saveData(data);
  res.json({ ok: true });
});

app.post("/api/services", (req, res) => {
  const data = loadData();
  const group = data.groups.find(g => g.name === req.body.group);
  if (!group) return res.status(404).json({ error: "Group not found" });
  group.services.push({
    name: req.body.name,
    description: req.body.description,
    price: req.body.price,
    duration: req.body.duration
  });
  saveData(data);
  res.json({ ok: true });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`✅ Server running on port ${PORT}`));
EOF

# --- data/services.json ---
cat <<'EOF' > data/services.json
{
  "groups": [
    {
      "name": "Ногтевой сервис",
      "services": [
        { "name": "Маникюр", "description": "Классический маникюр", "price": 1000, "duration": 60 },
        { "name": "Покрытие гель-лаком", "description": "Снятие и нанесение гель-лака", "price": 1500, "duration": 90 }
      ]
    },
    {
      "name": "Волосы",
      "services": [
        { "name": "Стрижка", "description": "Мужская/женская стрижка", "price": 1200, "duration": 45 },
        { "name": "Окрашивание", "description": "Тонирование и окрашивание волос", "price": 2500, "duration": 120 }
      ]
    }
  ]
}
EOF

# --- public/admin.html ---
cat <<'EOF' > public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <title>Админка — Услуги</title>
  <link rel="stylesheet" href="admin.css" />
</head>
<body>
  <h1>Услуги и группы</h1>
  <div id="groups"></div>
  <script src="admin.js"></script>
</body>
</html>
EOF

# --- public/admin.css ---
cat <<'EOF' > public/admin.css
body {
  font-family: sans-serif;
  margin: 2em;
  background: #fafafa;
}
h1 {
  color: #333;
}
.group {
  background: #fff;
  margin: 1em 0;
  padding: 1em;
  border-radius: 8px;
  box-shadow: 0 1px 4px rgba(0,0,0,0.1);
}
.service {
  margin-left: 1em;
}
EOF

# --- public/admin.js ---
cat <<'EOF' > public/admin.js
async function loadGroups() {
  const res = await fetch('/api/groups');
  const groups = await res.json();
  const container = document.getElementById('groups');
  container.innerHTML = '';
  for (const g of groups) {
    const div = document.createElement('div');
    div.className = 'group';
    div.innerHTML = `<h2>${g.name}</h2>`;
    for (const s of g.services) {
      const serv = document.createElement('div');
      serv.className = 'service';
      serv.textContent = \`\${s.name} — \${s.price}₽, \${s.duration} мин\`;
      div.appendChild(serv);
    }
    container.appendChild(div);
  }
}
loadGroups();
EOF

echo ">>> Installing dependencies..."
npm install

echo ">>> Starting server..."
node server.js