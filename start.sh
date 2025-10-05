#!/bin/bash
set -e

echo ">>> Развёртывание мини-приложения (сервер + админка)..."

# === 1. Создание структуры ===
mkdir -p /app/{data,public}
cd /app

# === 2. Инициализация JSON-базы ===
cat <<'EOF' > data/services.json
{
  "groups": [
    { "id": 1, "name": "Ногтевой сервис" },
    { "id": 2, "name": "Волосы" }
  ],
  "services": [
    { "id": 1, "groupId": 1, "name": "Маникюр", "price": 1000, "duration": 60 },
    { "id": 2, "groupId": 2, "name": "Стрижка", "price": 1500, "duration": 45 }
  ]
}
EOF

# === 3. Сервер (чистый Node.js, ESM) ===
cat <<'EOF' > server.js
import { createServer } from "http";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { parse } from "url";
import { join } from "path";

const PORT = process.env.PORT || 8080;
const DATA_FILE = "./data/services.json";

function loadData() {
  if (!existsSync(DATA_FILE)) return { groups: [], services: [] };
  return JSON.parse(readFileSync(DATA_FILE, "utf8"));
}

function saveData(data) {
  writeFileSync(DATA_FILE, JSON.stringify(data, null, 2), "utf8");
}

const server = createServer((req, res) => {
  const { pathname } = parse(req.url, true);
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  if (pathname.startsWith("/api")) {
    let data = loadData();

    if (req.method === "GET" && pathname === "/api/groups") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(data.groups));
      return;
    }

    if (req.method === "GET" && pathname === "/api/services") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(data.services));
      return;
    }

    if (req.method === "POST" && pathname === "/api/services") {
      let body = "";
      req.on("data", chunk => (body += chunk));
      req.on("end", () => {
        const service = JSON.parse(body);
        service.id = Date.now();
        data.services.push(service);
        saveData(data);
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(service));
      });
      return;
    }

    if (req.method === "PUT" && pathname.startsWith("/api/services/")) {
      const id = parseInt(pathname.split("/").pop());
      let body = "";
      req.on("data", chunk => (body += chunk));
      req.on("end", () => {
        const updated = JSON.parse(body);
        data.services = data.services.map(s => (s.id === id ? updated : s));
        saveData(data);
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(updated));
      });
      return;
    }

    if (req.method === "DELETE" && pathname.startsWith("/api/services/")) {
      const id = parseInt(pathname.split("/").pop());
      data.services = data.services.filter(s => s.id !== id);
      saveData(data);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ success: true }));
      return;
    }

    res.writeHead(404);
    res.end("Not found");
    return;
  }

  // === Отдача админки ===
  const filePath =
    pathname === "/" ? "public/admin.html" : join("public", pathname);
  try {
    const content = readFileSync(filePath);
    res.writeHead(200);
    res.end(content);
  } catch {
    res.writeHead(404);
    res.end("Файл не найден");
  }
});

server.listen(PORT, () =>
  console.log(`✅ Сервер запущен на порту ${PORT}`)
);
EOF

# === 4. Интерфейс админки (HTML + CSS + JS) ===
cat <<'EOF' > public/admin.html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Админка — Услуги</title>
  <link rel="stylesheet" href="admin.css">
</head>
<body>
  <h1>Услуги и группы</h1>
  <div class="form">
    <input id="name" placeholder="Название услуги">
    <input id="price" type="number" placeholder="Цена">
    <input id="duration" type="number" placeholder="Длительность (мин)">
    <select id="group"></select>
    <button onclick="addService()">Добавить</button>
  </div>
  <div id="services"></div>
  <script src="admin.js"></script>
</body>
</html>
EOF

cat <<'EOF' > public/admin.css
body {
  font-family: system-ui, sans-serif;
  background: #fafafa;
  color: #333;
  max-width: 700px;
  margin: 40px auto;
}
h1 { text-align: center; }
.form {
  display: flex;
  gap: 6px;
  margin-bottom: 15px;
}
input, select, button {
  padding: 8px;
  border-radius: 6px;
  border: 1px solid #ccc;
}
button {
  background: #007bff;
  color: #fff;
  cursor: pointer;
}
button:hover { background: #0056b3; }
.service {
  display: flex;
  justify-content: space-between;
  background: #fff;
  margin: 5px 0;
  padding: 8px;
  border-radius: 6px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
}
EOF

cat <<'EOF' > public/admin.js
async function fetchJSON(url, options) {
  const res = await fetch(url, options);
  return res.json();
}

async function loadGroups() {
  const groups = await fetchJSON("/api/groups");
  const sel = document.getElementById("group");
  sel.innerHTML = groups.map(g => `<option value="${g.id}">${g.name}</option>`).join("");
}

async function loadServices() {
  const data = await fetchJSON("/api/services");
  const div = document.getElementById("services");
  div.innerHTML = data.map(s => `
    <div class="service">
      <div>
        <b>${s.name}</b> — ${s.price} ₽, ${s.duration} мин
      </div>
      <div>
        <button onclick="editService(${s.id})">✎</button>
        <button onclick="deleteService(${s.id})">🗑</button>
      </div>
    </div>
  `).join("");
}

async function addService() {
  const name = document.getElementById("name").value;
  const price = parseInt(document.getElementById("price").value);
  const duration = parseInt(document.getElementById("duration").value);
  const groupId = parseInt(document.getElementById("group").value);
  await fetchJSON("/api/services", {
    method: "POST",
    headers: {"Content-Type":"application/json"},
    body: JSON.stringify({ name, price, duration, groupId })
  });
  await loadServices();
}

async function deleteService(id) {
  await fetch(`/api/services/${id}`, { method: "DELETE" });
  await loadServices();
}

function editService(id) {
  alert("Редактирование пока не реализовано");
}

loadGroups();
loadServices();
EOF

# === 5. Запуск ===
echo ">>> Запуск сервера..."
node server.js