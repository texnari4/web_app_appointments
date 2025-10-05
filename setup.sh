#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(pwd)"
echo ">> Creating project at: $PROJECT_ROOT"

mkdir -p src public/admin docker

############################################
# package.json
############################################
cat > package.json <<'EOF'
{
  "name": "beautyminiappappointments",
  "version": "4.0.0",
  "type": "module",
  "private": true,
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "start": "node dist/index.js",
    "dev": "node --watch --loader ts-node/esm src/index.ts"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "express": "^4.21.2",
    "pino": "^9.13.1",
    "pino-http": "^10.5.0"
  },
  "devDependencies": {
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^20.11.30",
    "ts-node": "^10.9.2",
    "typescript": "^5.6.3"
  }
}
EOF

############################################
# tsconfig.json
############################################
cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
EOF

############################################
# src/db.ts — простая файловая БД (JSON)
############################################
cat > src/db.ts <<'EOF'
import { mkdir, readFile, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const FILES = {
  masters: 'masters.json',
  services: 'services.json',
  appointments: 'appointments.json',
  clients: 'clients.json'
};

type Id = string;

export interface Master {
  id: Id;
  name: string;
  phone?: string;
  avatarUrl?: string;
  isActive?: boolean;
  specialties?: string[];
  description?: string;
  schedule?: {
    type: 'weekly' | 'custom';
    weekly?: { // 0-6: вс-сб
      [weekday: string]: { from: string; to: string }[]; 
    };
    custom?: { date: string; slots: { from: string; to: string }[] }[];
  }
  createdAt: string;
  updatedAt: string;
}

export interface Service {
  id: Id;
  group: string;           // категория (Ногтевой сервис, Волосы, ...)
  title: string;
  description?: string;
  price: number;
  durationMin: number;     // длительность в минутах
  createdAt: string;
  updatedAt: string;
}

export interface Client {
  id: Id;
  name: string;
  phone?: string;
  tg?: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export interface Appointment {
  id: Id;
  masterId: Id;
  serviceId: Id;
  clientId: Id;
  date: string;       // YYYY-MM-DD
  timeFrom: string;   // HH:mm
  timeTo: string;     // HH:mm
  price?: number;     // фиксируется на момент записи
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

async function ensureDataDir() {
  await mkdir(DATA_DIR, { recursive: true });
}

async function filePath(kind: keyof typeof FILES) {
  await ensureDataDir();
  return path.join(DATA_DIR, FILES[kind]);
}

async function readJson<T>(kind: keyof typeof FILES): Promise<T[]> {
  const fp = await filePath(kind);
  try {
    await access(fp);
  } catch {
    await writeFile(fp, '[]', 'utf-8');
  }
  const raw = await readFile(fp, 'utf-8');
  try {
    const arr = JSON.parse(raw);
    if (Array.isArray(arr)) return arr as T[];
    return [];
  } catch {
    return [];
  }
}

async function writeJson<T>(kind: keyof typeof FILES, arr: T[]) {
  const fp = await filePath(kind);
  await writeFile(fp, JSON.stringify(arr, null, 2), 'utf-8');
}

function nowISO() {
  return new Date().toISOString();
}
function newId() {
  return crypto.randomUUID();
}

export const db = {
  async listMasters() { return readJson<Master>('masters'); },
  async upsertMaster(payload: Partial<Master> & { id?: Id }) {
    const list = await readJson<Master>('masters');
    if (payload.id) {
      const idx = list.findIndex(x => x.id === payload.id);
      if (idx >= 0) {
        list[idx] = { ...list[idx], ...payload, updatedAt: nowISO() } as Master;
      } else {
        const now = nowISO();
        list.push({ id: payload.id, name: payload.name || '', isActive: true, createdAt: now, updatedAt: now, ...payload } as Master);
      }
    } else {
      const now = nowISO();
      list.push({ id: newId(), name: payload.name || '', isActive: true, createdAt: now, updatedAt: now, ...payload } as Master);
    }
    await writeJson('masters', list);
    return list[list.length - 1];
  },
  async deleteMaster(id: Id) {
    const list = await readJson<Master>('masters');
    const next = list.filter(x => x.id !== id);
    await writeJson('masters', next);
    return { ok: true };
  },

  async listServices() { return readJson<Service>('services'); },
  async upsertService(payload: Partial<Service> & { id?: Id }) {
    const list = await readJson<Service>('services');
    const now = nowISO();
    if (payload.id) {
      const i = list.findIndex(x => x.id === payload.id);
      if (i >= 0) list[i] = { ...list[i], ...payload, updatedAt: now } as Service;
      else list.push({ id: payload.id, title: payload.title || '', group: payload.group || 'Общее', price: payload.price ?? 0, durationMin: payload.durationMin ?? 60, createdAt: now, updatedAt: now, ...payload } as Service);
    } else {
      list.push({ id: newId(), title: payload.title || '', group: payload.group || 'Общее', price: payload.price ?? 0, durationMin: payload.durationMin ?? 60, createdAt: now, updatedAt: now, ...payload } as Service);
    }
    await writeJson('services', list);
    return list[list.length - 1];
  },
  async deleteService(id: Id) {
    const list = await readJson<Service>('services');
    const next = list.filter(x => x.id !== id);
    await writeJson('services', next);
    return { ok: true };
  },

  async listAppointments() { return readJson<Appointment>('appointments'); },
  async upsertAppointment(payload: Partial<Appointment> & { id?: Id }) {
    const list = await readJson<Appointment>('appointments');
    const now = nowISO();
    if (payload.id) {
      const i = list.findIndex(x => x.id === payload.id);
      if (i >= 0) list[i] = { ...list[i], ...payload, updatedAt: now } as Appointment;
      else list.push({ id: payload.id, createdAt: now, updatedAt: now, ...(payload as any) });
    } else {
      list.push({ id: newId(), createdAt: now, updatedAt: now, ...(payload as any) });
    }
    await writeJson('appointments', list);
    return list[list.length - 1];
  },
  async deleteAppointment(id: Id) {
    const list = await readJson<Appointment>('appointments');
    const next = list.filter(x => x.id !== id);
    await writeJson('appointments', next);
    return { ok: true };
  },

  async listClients() { return readJson<Client>('clients'); },
  async upsertClient(payload: Partial<Client> & { id?: Id }) {
    const list = await readJson<Client>('clients');
    const now = nowISO();
    if (payload.id) {
      const i = list.findIndex(x => x.id === payload.id);
      if (i >= 0) list[i] = { ...list[i], ...payload, updatedAt: now } as Client;
      else list.push({ id: payload.id, name: payload.name || '', createdAt: now, updatedAt: now, ...payload } as Client);
    } else {
      list.push({ id: newId(), name: payload.name || '', createdAt: now, updatedAt: now, ...payload } as Client);
    }
    await writeJson('clients', list);
    return list[list.length - 1];
  },
  async deleteClient(id: Id) {
    const list = await readJson<Client>('clients');
    const next = list.filter(x => x.id !== id);
    await writeJson('clients', next);
    return { ok: true };
  }
};
EOF

############################################
# src/index.ts — сервер, API и админка
############################################
cat > src/index.ts <<'EOF'
import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { db } from './db.js';

const PORT = Number(process.env.PORT || 8080);
const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');

const app = express();
const logger = pino();
app.use(pinoHttp({ logger }));
app.use(cors());
app.use(express.json());

// Статика: /public/* (CSS/JS/картинки и т.д.)
app.use('/public', express.static(path.join(process.cwd(), 'public'), { fallthrough: true }));

/** ----------- Masters ----------- */
app.get('/public/api/masters', async (_req, res) => {
  res.json({ items: await db.listMasters() });
});
app.post('/public/api/masters', async (req, res) => {
  const created = await db.upsertMaster(req.body || {});
  res.json(created);
});
app.put('/public/api/masters/:id', async (req, res) => {
  const created = await db.upsertMaster({ ...(req.body || {}), id: req.params.id });
  res.json(created);
});
app.delete('/public/api/masters/:id', async (req, res) => {
  res.json(await db.deleteMaster(req.params.id));
});

/** ----------- Services ----------- */
app.get('/public/api/services', async (_req, res) => {
  res.json({ items: await db.listServices() });
});
app.post('/public/api/services', async (req, res) => {
  const created = await db.upsertService(req.body || {});
  res.json(created);
});
app.put('/public/api/services/:id', async (req, res) => {
  const created = await db.upsertService({ ...(req.body || {}), id: req.params.id });
  res.json(created);
});
app.delete('/public/api/services/:id', async (req, res) => {
  res.json(await db.deleteService(req.params.id));
});

/** ----------- Appointments ----------- */
app.get('/public/api/appointments', async (_req, res) => {
  res.json({ items: await db.listAppointments() });
});
app.post('/public/api/appointments', async (req, res) => {
  const created = await db.upsertAppointment(req.body || {});
  res.json(created);
});
app.put('/public/api/appointments/:id', async (req, res) => {
  const created = await db.upsertAppointment({ ...(req.body || {}), id: req.params.id });
  res.json(created);
});
app.delete('/public/api/appointments/:id', async (req, res) => {
  res.json(await db.deleteAppointment(req.params.id));
});

/** ----------- Clients ----------- */
app.get('/public/api/clients', async (_req, res) => {
  res.json({ items: await db.listClients() });
});
app.post('/public/api/clients', async (req, res) => {
  const created = await db.upsertClient(req.body || {});
  res.json(created);
});
app.put('/public/api/clients/:id', async (req, res) => {
  const created = await db.upsertClient({ ...(req.body || {}), id: req.params.id });
  res.json(created);
});
app.delete('/public/api/clients/:id', async (req, res) => {
  res.json(await db.deleteClient(req.params.id));
});

/** ----------- Admin UI ----------- */
// /admin — отдаем готовую страницу из public/admin/index.html
app.get(['/admin', '/admin/'], (_req, res) => {
  res.sendFile(path.join(process.cwd(), 'public', 'admin', 'index.html'));
});

app.get('/', (_req, res) => {
  res.type('text').send(`OK
DATA_DIR=${DATA_DIR}
`);
});

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
  logger.info(`DATA_DIR=${DATA_DIR}`);
});
EOF

############################################
# public/admin/index.html — дизайн (inline CSS), стабильная версия
############################################
cat > public/admin/index.html <<'EOF'
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Админка · Beauty</title>
<style>
  :root { --bg:#0f172a; --card:#111827; --muted:#94a3b8; --txt:#e5e7eb; --acc:#6366f1; --ok:#22c55e; --bad:#ef4444; }
  * { box-sizing:border-box; }
  html, body { height:100%; }
  body { margin:0; background:linear-gradient(180deg,#0b1221,#0f172a); color:var(--txt); font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial; }
  .shell { max-width:1100px; margin:24px auto; padding:0 16px; }
  .top { display:flex; align-items:center; gap:12px; margin-bottom:16px; }
  .brand { font-size:20px; font-weight:700; letter-spacing:.3px; }
  .tabs { display:flex; gap:8px; flex-wrap:wrap; }
  .tab { border:1px solid #1f2937; background:#0b1221; color:var(--muted); padding:8px 12px; border-radius:10px; cursor:pointer; }
  .tab.active { color:#fff; border-color:#2e3b52; background:#111827; }
  .grid { display:grid; grid-template-columns: 1.2fr .8fr; gap:16px; margin-top:16px; }
  .card { background:var(--card); border:1px solid #1f2937; border-radius:16px; padding:16px; }
  .card h3 { margin:0 0 12px; font-size:16px; }
  .list { display:flex; flex-direction:column; gap:8px; }
  .row { display:flex; justify-content:space-between; align-items:center; gap:12px; padding:10px; border:1px solid #1f2937; border-radius:12px; background:#0b1221; }
  .row .meta { display:flex; flex-direction:column; }
  .row .meta .name { font-weight:600; }
  .row .meta .sub { color:var(--muted); font-size:12px; }
  .row .actions { display:flex; gap:6px; }
  .btn { border:1px solid #2e3b52; background:#0f172a; color:#fff; padding:8px 10px; border-radius:10px; cursor:pointer; }
  .btn:hover { border-color:#3f4d6b; }
  .btn.ok { border-color:#1b5e2b; background:#0f1a12; }
  .btn.bad { border-color:#6b1f1f; background:#1a0f0f; }
  form .fld { display:flex; gap:8px; margin-bottom:8px; }
  form input, form select, form textarea { width:100%; padding:8px 10px; border-radius:10px; border:1px solid #334155; background:#0b1221; color:#fff; }
  .muted { color:var(--muted); }
  .hint { font-size:12px; color:var(--muted); margin-top:6px; }
  .footer { text-align:center; margin-top:14px; color:var(--muted); font-size:12px; }
  @media (max-width:900px) { .grid { grid-template-columns: 1fr; } }
</style>
</head>
<body>
  <div class="shell">
    <div class="top">
      <div class="brand">Beauty · Admin</div>
      <div class="tabs">
        <button class="tab active" data-tab="masters">Мастера</button>
        <button class="tab" data-tab="services">Услуги</button>
        <button class="tab" data-tab="appointments">Записи</button>
        <button class="tab" data-tab="clients">Клиенты</button>
      </div>
    </div>

    <div id="content"></div>
    <div class="footer">DATA_DIR отображается в / (корне) ответа API</div>
  </div>

<script>
const api = {
  get: (url) => fetch(url).then(r => { if(!r.ok) throw new Error(`${r.status} ${url}`); return r.json(); }),
  post: (url, data) => fetch(url, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)}).then(r => r.json()),
  put: (url, data) => fetch(url, {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)}).then(r => r.json()),
  del: (url) => fetch(url, {method:'DELETE'}).then(r => r.json())
};

const el = sel => document.querySelector(sel);
const content = el('#content');

async function loadMasters() {
  const data = await api.get('/public/api/masters');
  const items = data.items || [];
  content.innerHTML = `
    <div class="grid">
      <div class="card">
        <h3>Список мастеров</h3>
        <div class="list" id="masters-list">
          ${items.map(it => `
            <div class="row">
              <div class="meta">
                <div class="name">${it.name || 'Без имени'}</div>
                <div class="sub">${it.phone || ''}</div>
              </div>
              <div class="actions">
                <button class="btn" onclick='editMaster(${JSON.stringify(it).replace(/"/g,"&quot;")})'>Ред.</button>
                <button class="btn bad" onclick='deleteMaster("${it.id}")'>Удалить</button>
              </div>
            </div>
          `).join('') || '<div class="muted">Пока пусто</div>'}
        </div>
      </div>
      <div class="card">
        <h3>Добавить / Редактировать</h3>
        <form onsubmit="return saveMaster(event)">
          <input type="hidden" id="m_id" />
          <div class="fld"><input id="m_name" placeholder="Имя" required></div>
          <div class="fld"><input id="m_phone" placeholder="Телефон"></div>
          <div class="fld"><input id="m_avatar" placeholder="URL аватара"></div>
          <div class="fld"><input id="m_specialties" placeholder="Специальности (через запятую)"></div>
          <div class="fld"><textarea id="m_desc" rows="3" placeholder="Описание"></textarea></div>
          <div class="fld"><button class="btn ok" type="submit">Сохранить</button></div>
          <div class="hint">График добавим отдельным шагом.</div>
        </form>
      </div>
    </div>
  `;
  window.deleteMaster = async (id) => { await api.del('/public/api/masters/'+id); loadMasters(); };
  window.editMaster = (it) => {
    el('#m_id').value = it.id || '';
    el('#m_name').value = it.name || '';
    el('#m_phone').value = it.phone || '';
    el('#m_avatar').value = it.avatarUrl || '';
    el('#m_specialties').value = (it.specialties||[]).join(', ');
    el('#m_desc').value = it.description || '';
  };
  window.saveMaster = async (ev) => {
    ev.preventDefault();
    const payload = {
      name: el('#m_name').value.trim(),
      phone: el('#m_phone').value.trim(),
      avatarUrl: el('#m_avatar').value.trim(),
      specialties: el('#m_specialties').value.split(',').map(s => s.trim()).filter(Boolean),
      description: el('#m_desc').value.trim(),
      isActive: true
    };
    const id = el('#m_id').value;
    if (id) await api.put('/public/api/masters/'+id, payload);
    else await api.post('/public/api/masters', payload);
    ev.target.reset();
    loadMasters();
    return false;
  };
}

async function loadServices() {
  const data = await api.get('/public/api/services');
  const items = data.items || [];

  content.innerHTML = `
    <div class="grid">
      <div class="card">
        <h3>Услуги</h3>
        <div class="list">
          ${items.map(it => `
            <div class="row">
              <div class="meta">
                <div class="name">${it.title} — <span class="muted">${it.group}</span></div>
                <div class="sub">${(it.durationMin||0)} мин · ${(it.price||0)} BYN</div>
              </div>
              <div class="actions">
                <button class="btn" onclick='editService(${JSON.stringify(it).replace(/"/g,"&quot;")})'>Ред.</button>
                <button class="btn bad" onclick='deleteService("${it.id}")'>Удалить</button>
              </div>
            </div>
          `).join('') || '<div class="muted">Пока пусто</div>'}
        </div>
      </div>
      <div class="card">
        <h3>Добавить / Редактировать услугу</h3>
        <form onsubmit="return saveService(event)">
          <input type="hidden" id="s_id" />
          <div class="fld"><input id="s_group" placeholder="Группа (напр. Ногтевой сервис)" required></div>
          <div class="fld"><input id="s_title" placeholder="Название" required></div>
          <div class="fld"><textarea id="s_desc" rows="3" placeholder="Описание"></textarea></div>
          <div class="fld"><input id="s_price" type="number" step="0.01" placeholder="Цена" required></div>
          <div class="fld"><input id="s_dur" type="number" step="5" placeholder="Длительность, мин" required></div>
          <div class="fld"><button class="btn ok" type="submit">Сохранить</button></div>
        </form>
      </div>
    </div>
  `;
  window.deleteService = async (id) => { await api.del('/public/api/services/'+id); loadServices(); };
  window.editService = (it) => {
    el('#s_id').value = it.id || '';
    el('#s_group').value = it.group || '';
    el('#s_title').value = it.title || '';
    el('#s_desc').value = it.description || '';
    el('#s_price').value = it.price ?? 0;
    el('#s_dur').value = it.durationMin ?? 60;
  };
  window.saveService = async (ev) => {
    ev.preventDefault();
    const payload = {
      group: el('#s_group').value.trim(),
      title: el('#s_title').value.trim(),
      description: el('#s_desc').value.trim(),
      price: Number(el('#s_price').value),
      durationMin: Number(el('#s_dur').value)
    };
    const id = el('#s_id').value;
    if (id) await api.put('/public/api/services/'+id, payload);
    else await api.post('/public/api/services', payload);
    ev.target.reset();
    loadServices();
    return false;
  };
}

async function loadAppointments() {
  const data = await api.get('/public/api/appointments');
  const items = data.items || [];
  content.innerHTML = `
    <div class="card">
      <h3>Записи</h3>
      <div class="list">
        ${items.map(it => `
          <div class="row">
            <div class="meta">
              <div class="name">${it.date} ${it.timeFrom}–${it.timeTo}</div>
              <div class="sub">master:${it.masterId} · service:${it.serviceId} · client:${it.clientId}</div>
            </div>
            <div class="actions">
              <button class="btn bad" onclick='deleteAp("${it.id}")'>Удалить</button>
            </div>
          </div>
        `).join('') || '<div class="muted">Пока пусто</div>'}
      </div>
      <div class="hint">Форму создания добавим в следующем шаге (зависит от расписания мастеров).</div>
    </div>
  `;
  window.deleteAp = async (id) => { await api.del('/public/api/appointments/'+id); loadAppointments(); };
}

async function loadClients() {
  const data = await api.get('/public/api/clients');
  const items = data.items || [];
  content.innerHTML = `
    <div class="grid">
      <div class="card">
        <h3>Клиенты</h3>
        <div class="list">
          ${items.map(it => `
            <div class="row">
              <div class="meta">
                <div class="name">${it.name}</div>
                <div class="sub">${it.phone || ''}</div>
              </div>
              <div class="actions">
                <button class="btn bad" onclick='deleteClient("${it.id}")'>Удалить</button>
              </div>
            </div>
          `).join('') || '<div class="muted">Пока пусто</div>'}
        </div>
      </div>
      <div class="card">
        <h3>Добавить клиента</h3>
        <form onsubmit="return saveClient(event)">
          <div class="fld"><input id="c_name" placeholder="Имя" required></div>
          <div class="fld"><input id="c_phone" placeholder="Телефон"></div>
          <div class="fld"><button class="btn ok" type="submit">Сохранить</button></div>
        </form>
      </div>
    </div>
  `;
  window.deleteClient = async (id) => { await api.del('/public/api/clients/'+id); loadClients(); };
  window.saveClient = async (ev) => {
    ev.preventDefault();
    const payload = { name: el('#c_name').value.trim(), phone: el('#c_phone').value.trim() };
    await api.post('/public/api/clients', payload);
    ev.target.reset();
    loadClients();
    return false;
  };
}

function bindTabs() {
  document.querySelectorAll('.tab').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach(b=>b.classList.remove('active'));
      btn.classList.add('active');
      const tab = btn.dataset.tab;
      if (tab === 'masters') loadMasters();
      if (tab === 'services') loadServices();
      if (tab === 'appointments') loadAppointments();
      if (tab === 'clients') loadClients();
    });
  });
}

bindTabs();
loadMasters(); // default
</script>
</body>
</html>
EOF

############################################
# Dockerfile — multi-stage без chown/chmod на volume
############################################
cat > Dockerfile <<'EOF'
# --- Build stage ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
COPY public ./public
RUN npm run build

# --- Runtime stage ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV DATA_DIR=/app/data
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh
EXPOSE 8080
CMD ["./entrypoint.sh"]
EOF

############################################
# docker/entrypoint.sh
############################################
cat > docker/entrypoint.sh <<'EOF'
#!/usr/bin/env sh
set -e
echo "Starting app with DATA_DIR=${DATA_DIR:-/app/data}"
mkdir -p "${DATA_DIR:-/app/data}"
node dist/index.js
EOF

############################################
# .dockerignore
############################################
cat > .dockerignore <<'EOF'
node_modules
dist
data
npm-debug.log
Dockerfile*
docker-compose*
.git
.gitignore
EOF

############################################
# Тестовые данные (опционально)
############################################
mkdir -p data
cat > data/masters.json <<'EOF'
[
  {
    "id": "seed-1",
    "name": "Юлия",
    "phone": "+375331126113",
    "avatarUrl": "http://testurl.com",
    "isActive": true,
    "specialties": ["Ногти","Брови"],
    "description": "Мастер со стажем",
    "createdAt": "2025-10-05T09:42:52.879Z",
    "updatedAt": "2025-10-05T09:42:52.879Z"
  }
]
EOF
cat > data/services.json <<'EOF'
[
  {
    "id": "svc-1",
    "group": "Ногтевой сервис",
    "title": "Маникюр классический",
    "description": "Уход за ногтями",
    "price": 35,
    "durationMin": 60,
    "createdAt": "2025-10-05T09:43:36.695Z",
    "updatedAt": "2025-10-05T09:43:36.695Z"
  }
]
EOF
echo "[]" > data/appointments.json
echo "[]" > data/clients.json

############################################
# Установка зависимостей и сборка
############################################
echo ">> Installing deps..."
npm install
echo ">> Building..."
npm run build

echo
echo "===================================================="
echo "✅ Проект готов."
echo "Локальный запуск:    npm start     (http://localhost:8080/admin)"
echo "Docker билд:         docker build -t beauty-admin ."
echo "Docker запуск:       docker run -p 8080:8080 -e DATA_DIR=/app/data -v \"$(pwd)/data:/app/data\" beauty-admin"
echo "===================================================="