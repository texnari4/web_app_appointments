#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'fs';
import { parse } from 'url';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import crypto from 'crypto';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(__dirname, 'data');
mkdirSync(DATA_DIR, { recursive: true });

const servicesFile = join(DATA_DIR, 'services.json');
const groupsFile = join(DATA_DIR, 'groups.json');
const bookingsFile = join(DATA_DIR, 'bookings.json');
const adminsFile = join(DATA_DIR, 'admins.json');
const mastersFile = join(DATA_DIR, 'masters.json');

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || null;
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || 'https://beautyminiappappointments-production.up.railway.app').replace(/\/+$/,'');
const TG_API = TELEGRAM_BOT_TOKEN ? `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}` : null;

async function tgSendMessage(chatId, text, extra = {}) {
  if (!TG_API) return;
  try {
    await fetch(`${TG_API}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text, parse_mode: 'HTML', disable_web_page_preview: true, ...extra })
    });
  } catch {}
}

const GOOGLE_SHEET_ID = process.env.GOOGLE_SHEET_ID || '1eHQ43tJYemxZJZGE8VDPJQ9duol7RHdbbNTPhUrTwLc';
const GOOGLE_SERVICE_ACCOUNT_JSON = process.env.GOOGLE_SERVICE_ACCOUNT_JSON || null;
const GOOGLE_TOKEN_AUD = 'https://oauth2.googleapis.com/token';
const GOOGLE_SHEETS_SCOPE = 'https://www.googleapis.com/auth/spreadsheets';

const SLOT_STEP_MIN = Number(process.env.SLOT_STEP_MIN || 30);
const BUSINESS_OPEN_TIME = process.env.BUSINESS_OPEN_TIME || '09:00';
const BUSINESS_CLOSE_TIME = process.env.BUSINESS_CLOSE_TIME || '21:00';

const DEFAULT_GROUPS = [
  { id: 1, name: 'Массаж' },
  { id: 2, name: 'Парикмахерские услуги' },
  { id: 3, name: 'Ногтевой сервис' }
];

function makeBackupName() {
  const d = new Date();
  const dd = String(d.getDate()).padStart(2,'0');
  const mm = String(d.getMonth()+1).padStart(2,'0');
  const yyyy = d.getFullYear();
  return `time:${dd}.${mm}.${yyyy}.zip`;
}

const DEFAULT_SERVICES = [
  {
    id: 1,
    name: 'Массаж спины',
    description: 'Классический расслабляющий массаж спины и плечевого пояса',
    price: 1500,
    duration: 60,
    groupId: 1
  },
  {
    id: 2,
    name: 'Стрижка женская',
    description: 'Мытьё, укладка, стрижка с учётом особенностей волос',
    price: 1200,
    duration: 60,
    groupId: 2
  },
  {
    id: 3,
    name: 'Классический маникюр',
    description: 'Комплексная обработка ногтей и кутикулы',
    price: 1000,
    duration: 60,
    groupId: 3
  }
];

const DEFAULT_BOOKINGS = [];
const DEFAULT_MASTERS = [];

const DEFAULT_ADMINS = [
  {
    id: 486778995,
    username: 'mr_tenbit',
    displayName: 'mr_tenbit',
    role: 'owner'
  }
];

function ensureDataFile(file, fallback) {
  if (!existsSync(file)) {
    writeFileSync(file, JSON.stringify(fallback, null, 2));
    return;
  }

  try {
    const raw = readFileSync(file, 'utf-8');
    if (raw.trim() === '') {
      writeFileSync(file, JSON.stringify(fallback, null, 2));
    } else {
      JSON.parse(raw);
    }
  } catch (err) {
    console.warn(`⚠️  Не удалось прочитать ${file}. Пересоздаю с тестовыми данными.`);
    writeFileSync(file, JSON.stringify(fallback, null, 2));
  }
}

ensureDataFile(groupsFile, DEFAULT_GROUPS);
ensureDataFile(servicesFile, DEFAULT_SERVICES);
ensureDataFile(bookingsFile, DEFAULT_BOOKINGS);
ensureDataFile(adminsFile, DEFAULT_ADMINS);
ensureDataFile(mastersFile, DEFAULT_MASTERS);

function readJSON(file, fallback = []) {
  try {
    return JSON.parse(readFileSync(file, 'utf-8'));
  } catch (err) {
    console.error(`Ошибка чтения ${file}:`, err);
    return fallback;
  }
}

function writeJSON(file, data) {
  writeFileSync(file, JSON.stringify(data, null, 2));
}

async function getGoogleAccessToken() {
  if (!GOOGLE_SERVICE_ACCOUNT_JSON) {
    throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON not set');
  }
  let creds;
  try { creds = JSON.parse(GOOGLE_SERVICE_ACCOUNT_JSON); } catch (e) { throw new Error('Invalid GOOGLE_SERVICE_ACCOUNT_JSON'); }
  const { client_email, private_key } = creds;
  if (!client_email || !private_key) throw new Error('Service account creds missing client_email/private_key');

  const now = Math.floor(Date.now()/1000);
  const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
  const claim = Buffer.from(JSON.stringify({ iss: client_email, scope: GOOGLE_SHEETS_SCOPE, aud: GOOGLE_TOKEN_AUD, exp: now + 3600, iat: now })).toString('base64url');
  const input = `${header}.${claim}`;
  const { createSign } = await import('node:crypto');
  const signature = createSign('RSA-SHA256').update(input).end().sign(private_key).toString('base64url');
  const jwt = `${input}.${signature}`;

  const resp = await fetch(GOOGLE_TOKEN_AUD, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }) });
  if (!resp.ok) { const t = await resp.text(); throw new Error(`Failed to get token: ${resp.status} ${t}`); }
  const json = await resp.json();
  return json.access_token;
}

async function sheetsValuesUpdate(spreadsheetId, range, values) {
  const token = await getGoogleAccessToken();
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${encodeURIComponent(range)}?valueInputOption=RAW`;
  const resp = await fetch(url, { method: 'PUT', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ range, values, majorDimension: 'ROWS' }) });
  if (!resp.ok) throw new Error(`Sheets update failed: ${resp.status}`);
  return await resp.json();
}

async function sheetsValuesClear(spreadsheetId, range) {
  const token = await getGoogleAccessToken();
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${encodeURIComponent(range)}:clear`;
  const resp = await fetch(url, { method: 'POST', headers: { 'Authorization': `Bearer ${token}` } });
  if (!resp.ok) throw new Error(`Sheets clear failed: ${resp.status}`);
  return await resp.json();
}

async function sheetsValuesGet(spreadsheetId, range) {
  const token = await getGoogleAccessToken();
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${encodeURIComponent(range)}`;
  const resp = await fetch(url, { headers: { 'Authorization': `Bearer ${token}` } });
  if (!resp.ok) throw new Error(`Sheets get failed: ${resp.status}`);
  return await resp.json();
}

function toCsvList(arr) { return Array.isArray(arr) ? arr.join(', ') : ''; }
function toNum(val) { const n = Number(val); return Number.isFinite(n) ? n : null; }

function sendJSON(res, statusCode, payload) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function sendText(res, statusCode, payload) {
  res.writeHead(statusCode, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(payload);
}

function parseCookies(req){
  const h = req.headers['cookie'];
  if(!h) return {};
  return Object.fromEntries(h.split(';').map(p=>p.trim().split('=')).map(([k,...v])=>[k, decodeURIComponent(v.join('='))]));
}
function setCookie(res, name, value, opts={}){
  const parts = [`${name}=${encodeURIComponent(value)}`];
  if(opts.path) parts.push(`Path=${opts.path}`); else parts.push('Path=/');
  if(opts.maxAge!=null) parts.push(`Max-Age=${opts.maxAge}`);
  if(opts.httpOnly!==false) parts.push('HttpOnly');
  if(opts.sameSite) parts.push(`SameSite=${opts.sameSite}`); else parts.push('SameSite=Lax');
  if(opts.secure!==false) parts.push('Secure');
  res.setHeader('Set-Cookie', [...(res.getHeader('Set-Cookie')||[]), parts.join('; ')]);
}

const ROLE_WEIGHT = {
  unknown: -1,
  guest: 0,
  admin: 2,
  owner: 3
};

function parseTelegramId(req) {
  // 1) Cookie (set after Telegram WebApp auth)
  try {
    const cookies = parseCookies(req);
    if (cookies.tg_id) {
      const c = Number(cookies.tg_id);
      if (Number.isFinite(c)) return c;
    }
  } catch {}

  // 2) Custom headers (for reverse-proxy or future use)
  const headerId = req.headers['x-telegram-id'] ?? req.headers['x-telegram-user-id'];
  if (headerId != null) {
    const numeric = Number(headerId);
    if (Number.isFinite(numeric)) {
      return numeric;
    }
  }

  // 3) Query param (?tg_id=...) — используется при открытии ссылки из бота
  const urlIdMatch = req.url && req.url.includes('?')
    ? Number(new URL(`http://localhost${req.url}`).searchParams.get('tg_id'))
    : NaN;
  if (Number.isFinite(urlIdMatch)) {
    return urlIdMatch;
  }

  return null;
}

function readAdmins() {
  return readJSON(adminsFile, []);
}

function writeAdmins(admins) {
  writeJSON(adminsFile, admins);
}

function authenticate(req) {
  const telegramId = parseTelegramId(req);
  if (!telegramId) {
    return { role: 'guest', telegramId: null, provided: false };
  }

  const admins = readAdmins();
  const adminEntry = admins.find((admin) => admin.id === telegramId);
  if (!adminEntry) {
    return { role: 'unknown', telegramId, provided: true };
  }

  const role = adminEntry.role === 'owner' ? 'owner' : 'admin';
  return { role, telegramId, provided: true, admin: adminEntry };
}

function hasRequiredRole(currentRole, allowedRoles) {
  const currentWeight = ROLE_WEIGHT[currentRole] ?? -1;
  return allowedRoles.some((role) => currentWeight >= (ROLE_WEIGHT[role] ?? 99));
}

function ensureAuthorized(ctx, res, allowedRoles = []) {
  if (allowedRoles.length === 0 || allowedRoles.includes('guest')) {
    return true;
  }

  if (!ctx.provided) {
    sendJSON(res, 401, { error: 'Требуется Telegram ID администратора' });
    return false;
  }

  if (ctx.role === 'unknown') {
    sendJSON(res, 403, { error: 'Telegram ID не найден в списке администраторов' });
    return false;
  }

  if (!hasRequiredRole(ctx.role, allowedRoles)) {
    sendJSON(res, 403, { error: 'Недостаточно прав для выполнения действия' });
    return false;
  }

  return true;
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf-8');
}

function parseId(pathname) {
  const id = Number(pathname.split('/').pop());
  return Number.isFinite(id) ? id : null;
}

function validateServicePayload(payload, groups) {
  if (!payload || typeof payload !== 'object') {
    return 'Некорректное тело запроса';
  }

  const trimmedName = String(payload.name ?? '').trim();
  const trimmedDescription = String(payload.description ?? '').trim();
  const price = Number(payload.price);
  const duration = Number(payload.duration);
  const groupId = payload.groupId == null || payload.groupId === '' ? null : Number(payload.groupId);

  if (!trimmedName) {
    return 'Название обязательно';
  }

  if (!trimmedDescription) {
    return 'Описание обязательно';
  }

  if (!Number.isFinite(price) || price < 0) {
    return 'Цена должна быть неотрицательным числом';
  }

  if (!Number.isFinite(duration) || duration <= 0) {
    return 'Длительность должна быть положительным числом (в минутах)';
  }

  if (duration % SLOT_STEP_MIN !== 0) {
    return `Длительность должна быть кратной ${SLOT_STEP_MIN} минутам`;
  }

  if (groupId != null && !groups.some((g) => g.id === groupId)) {
    return 'Указанная группа не найдена';
  }

  return null;
}

function validateGroupPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return 'Некорректное тело запроса';
  }

  const trimmedName = String(payload.name ?? '').trim();
  if (!trimmedName) {
    return 'Название группы обязательно';
  }

  return null;
}

const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const TIME_REGEX = /^\d{2}:\d{2}$/;

function timeToMinutes(value) {
  if (typeof value !== 'string' || !TIME_REGEX.test(value)) {
    return NaN;
  }
  const [hours, minutes] = value.split(':').map(Number);
  if (hours > 23 || minutes > 59) {
    return NaN;
  }
  return hours * 60 + minutes;
}

function minutesToTime(value) {
  const hours = Math.floor(value / 60)
    .toString()
    .padStart(2, '0');
  const minutes = (value % 60).toString().padStart(2, '0');
  return `${hours}:${minutes}`;
}

function alignDurationMinutes(value) {
  if (!Number.isFinite(value) || value <= 0) {
    return NaN;
  }
  return Math.max(SLOT_STEP_MIN, Math.ceil(value / SLOT_STEP_MIN) * SLOT_STEP_MIN);
}

function getWorkdayBounds() {
  const open = timeToMinutes(BUSINESS_OPEN_TIME);
  const close = timeToMinutes(BUSINESS_CLOSE_TIME);
  if (!Number.isFinite(open) || !Number.isFinite(close) || open >= close) {
    console.warn(
      '⚠️  BUSINESS_OPEN_TIME/BUSINESS_CLOSE_TIME заданы некорректно. Использую диапазон 09:00-21:00.'
    );
    return { open: 9 * 60, close: 21 * 60 };
  }
  return { open, close };
}

function buildDailySlots({ date, duration, masterId, bookings }) {
  const { open, close } = getWorkdayBounds();
  const normalizedDuration = Number(duration ?? SLOT_STEP_MIN);
  if (!Number.isFinite(normalizedDuration) || normalizedDuration <= 0) {
    return [];
  }

  const slotAlignedDuration = alignDurationMinutes(normalizedDuration);
  if (!Number.isFinite(slotAlignedDuration)) {
    return [];
  }

  const normalizedMasterId = masterId == null || masterId === '' ? '' : String(masterId);
  const relevantBookings = bookings.filter(
    (booking) => booking.date === date && String(booking.masterId ?? '') === normalizedMasterId
  );

  const busyRanges = relevantBookings
    .map((booking) => {
      const start = timeToMinutes(booking.startTime);
      const durationMinutes = Number(booking.duration ?? SLOT_STEP_MIN);
      if (!Number.isFinite(start) || !Number.isFinite(durationMinutes)) {
        return null;
      }
      return [start, start + durationMinutes];
    })
    .filter((range) => Array.isArray(range));

  const slots = [];
  for (let start = open; start + slotAlignedDuration <= close; start += SLOT_STEP_MIN) {
    const end = start + slotAlignedDuration;
    const conflict = busyRanges.some(([busyStart, busyEnd]) => {
      return Math.max(busyStart, start) < Math.min(busyEnd, end);
    });
    slots.push({
      startTime: minutesToTime(start),
      endTime: minutesToTime(end),
      available: !conflict
    });
  }

  return slots;
}

function validateBookingPayload(payload, services) {
  if (!payload || typeof payload !== 'object') {
    return 'Некорректное тело запроса';
  }

  const clientName = String(payload.clientName ?? '').trim();
  const clientPhone = String(payload.clientPhone ?? '').trim();
  const date = String(payload.date ?? '').trim();
  const startTime = String(payload.startTime ?? '').trim();
  const serviceId = Number(payload.serviceId);
  const masterId = payload.masterId == null || payload.masterId === '' ? null : String(payload.masterId).trim();

  if (!clientName) {
    return 'Имя клиента обязательно';
  }

  if (!clientPhone) {
    return 'Телефон клиента обязателен';
  }

  if (!DATE_REGEX.test(date)) {
    return 'Укажите дату в формате ГГГГ-ММ-ДД';
  }

  if (!TIME_REGEX.test(startTime)) {
    return 'Укажите время начала в формате ЧЧ:ММ';
  }

  if (!Number.isFinite(serviceId)) {
    return 'Укажите корректный идентификатор услуги';
  }

  const service = services.find((item) => item.id === serviceId);
  if (!service) {
    return 'Услуга не найдена';
  }

  if (masterId != null && masterId.length === 0) {
    return 'Укажите корректного мастера';
  }

  const start = timeToMinutes(startTime);
  if (!Number.isFinite(start) || start % SLOT_STEP_MIN !== 0) {
    return `Время начала должно соответствовать шагу ${SLOT_STEP_MIN} минут`;
  }

  const rawDuration = Number(payload.duration ?? service.duration ?? SLOT_STEP_MIN);
  const normalizedDuration = alignDurationMinutes(rawDuration);
  if (!Number.isFinite(normalizedDuration)) {
    return 'Длительность должна быть положительной';
  }

  payload.duration = normalizedDuration;

  return null;
}

const server = createServer(async (req, res) => {
  const { pathname, query } = parse(req.url, true);
  const ctx = authenticate(req);

  try {
    if (pathname === '/health') {
      const files = [
        { label: 'groups.json',   path: groupsFile,   get: () => readJSON(groupsFile, []) },
        { label: 'services.json', path: servicesFile, get: () => readJSON(servicesFile, []) },
        { label: 'admins.json',   path: adminsFile,   get: () => readJSON(adminsFile, []) },
        { label: 'masters.json',  path: mastersFile,  get: () => readJSON(mastersFile, []) },
        { label: 'bookings.json', path: bookingsFile, get: () => readJSON(bookingsFile, []) }
      ];
      const rowHtml = files.map(f => {
        try {
          const s = statSync(f.path);
          const size = s.size;
          const data = f.get();
          const count = Array.isArray(data) ? data.length : (data && typeof data === 'object' ? Object.keys(data).length : 0);
          return `<tr><td>${f.label}</td><td>${size}</td><td>${count}</td></tr>`;
        } catch {
          return `<tr><td>${f.label}</td><td>—</td><td>—</td></tr>`;
        }
      }).join('');
      const mem = process.memoryUsage();
      const uptime = `${Math.floor(process.uptime())}s`;
      const html = `<!doctype html>
<html lang="ru"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Health</title>
<style>body{font-family:system-ui,-apple-system,Segoe UI,Inter,sans-serif;background:#f6f7fb;color:#111827;margin:0;padding:24px}main{max-width:900px;margin:0 auto;display:grid;gap:16px}section{background:#fff;border:1px solid rgba(209,213,219,.5);border-radius:14px;padding:16px}table{width:100%;border-collapse:collapse}th,td{border-top:1px solid rgba(209,213,219,.6);padding:8px 10px;text-align:left}th{background:#f8fafc}</style>
</head><body><main>
<h1>Статус приложения</h1>
<section>
<p>Node.js: <b>${process.version}</b> · Uptime: <b>${uptime}</b></p>
<p>BASE_URL: <code>${PUBLIC_BASE_URL}</code> · Telegram bot: <b>${TELEGRAM_BOT_TOKEN ? 'configured' : 'not set'}</b></p>
<p>Memory RSS: <b>${mem.rss}</b>, Heap Used: <b>${mem.heapUsed}</b></p>
</section>
<section>
<h2>Файлы данных</h2>
<table><thead><tr><th>Файл</th><th>Размер (байт)</th><th>Количество записей</th></tr></thead><tbody>${rowHtml}</tbody></table>
</section>
<section>
<h2>Ссылки</h2>
<ul>
<li><a href="/client">/client</a></li>
<li><a href="/admin">/admin</a></li>
<li><a href="/api/backup/export">/api/backup/export</a> (zip)</li>
</ul>
</section>
</main></body></html>`;
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
      return;
    }

    if (pathname === '/api/admins/me' && req.method === 'GET') {
      const admins = readAdmins();
      const isAdmin = admins.some((admin) => admin.id === ctx.telegramId);
      sendJSON(res, 200, {
        authenticated: isAdmin,
        telegramId: ctx.telegramId,
        admin:
          admins.find((admin) => admin.id === ctx.telegramId) || null
      });
      return;
    }

    if (pathname === '/api/admins' && req.method === 'GET') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }

      const admins = readAdmins();
      sendJSON(res, 200, admins);
      return;
    }

    if (pathname === '/api/admins' && req.method === 'POST') {
      if (!ensureAuthorized(ctx, res, ['owner'])) {
        return;
      }

      const body = await readBody(req);
      const payload = JSON.parse(body || '{}');

      const admins = readAdmins();
      const id = Number(payload.id);
      const username = String(payload.username ?? '').trim();
      const displayName = String(payload.displayName ?? username).trim();
      const role = payload.role === 'owner' ? 'owner' : 'admin';

      if (!Number.isFinite(id) || id <= 0) {
        sendJSON(res, 400, { error: 'Укажите корректный Telegram ID' });
        return;
      }

      if (!username) {
        sendJSON(res, 400, { error: 'Укажите username администратора' });
        return;
      }

      if (admins.some((admin) => admin.id === id)) {
        sendJSON(res, 409, { error: 'Администратор с таким ID уже существует' });
        return;
      }

      const newAdmin = { id, username, displayName, role };
      admins.push(newAdmin);
      writeAdmins(admins);
      sendJSON(res, 201, newAdmin);
      return;
    }

    if (pathname.startsWith('/api/admins/') && req.method === 'DELETE') {
      if (!ensureAuthorized(ctx, res, ['owner'])) {
        return;
      }

      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор администратора' });
        return;
      }

      const admins = readAdmins();
      if (admins.length === 1 && admins[0].id === id) {
        sendJSON(res, 400, { error: 'Нельзя удалить последнего администратора' });
        return;
      }

      const remaining = admins.filter((admin) => admin.id !== id);
      if (remaining.length === admins.length) {
        sendJSON(res, 404, { error: 'Администратор не найден' });
        return;
      }

      writeAdmins(remaining);
      sendJSON(res, 200, { success: true });
      return;
    }

    if (pathname === '/api/groups' && req.method === 'GET') {
      const groups = readJSON(groupsFile, []);
      sendJSON(res, 200, groups);
      return;
    }

    if (pathname === '/api/groups' && req.method === 'POST') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const body = await readBody(req);
      const payload = JSON.parse(body || '{}');
      const error = validateGroupPayload(payload);
      if (error) {
        sendJSON(res, 400, { error });
        return;
      }

      const groups = readJSON(groupsFile, []);
      const newGroup = {
        id: Date.now(),
        name: String(payload.name).trim()
      };
      groups.push(newGroup);
      writeJSON(groupsFile, groups);
      sendJSON(res, 201, newGroup);
      return;
    }

    if (pathname.startsWith('/api/groups/') && req.method === 'PUT') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор группы' });
        return;
      }

      const body = await readBody(req);
      const payload = JSON.parse(body || '{}');
      const error = validateGroupPayload(payload);
      if (error) {
        sendJSON(res, 400, { error });
        return;
      }

      const groups = readJSON(groupsFile, []);
      const idx = groups.findIndex((g) => g.id === id);
      if (idx === -1) {
        sendJSON(res, 404, { error: 'Группа не найдена' });
        return;
      }

      groups[idx] = { ...groups[idx], name: String(payload.name).trim() };
      writeJSON(groupsFile, groups);
      sendJSON(res, 200, groups[idx]);
      return;
    }

    if (pathname.startsWith('/api/groups/') && req.method === 'DELETE') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор группы' });
        return;
      }

      const groups = readJSON(groupsFile, []);
      const nextGroups = groups.filter((g) => g.id !== id);
      if (nextGroups.length === groups.length) {
        sendJSON(res, 404, { error: 'Группа не найдена' });
        return;
      }

      writeJSON(groupsFile, nextGroups);

      const services = readJSON(servicesFile, []);
      const updatedServices = services.map((service) =>
        service.groupId === id ? { ...service, groupId: null } : service
      );
      writeJSON(servicesFile, updatedServices);

      sendJSON(res, 200, { success: true });
      return;
    }

    if (pathname === '/api/services' && req.method === 'GET') {
      const services = readJSON(servicesFile, []);
      const groupIdFilter = query.groupId ? Number(query.groupId) : null;
      const filtered = groupIdFilter
        ? services.filter((service) => service.groupId === groupIdFilter)
        : services;
      sendJSON(res, 200, filtered);
      return;
    }

    if (pathname === '/api/services' && req.method === 'POST') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const body = await readBody(req);
      const payload = JSON.parse(body || '{}');
      const groups = readJSON(groupsFile, []);
      const error = validateServicePayload(payload, groups);
      if (error) {
        sendJSON(res, 400, { error });
        return;
      }

      const services = readJSON(servicesFile, []);
      const newService = {
        id: Date.now(),
        name: String(payload.name).trim(),
        description: String(payload.description).trim(),
        price: Number(payload.price),
        duration: Number(payload.duration),
        groupId: payload.groupId == null || payload.groupId === '' ? null : Number(payload.groupId)
      };
      services.push(newService);
      writeJSON(servicesFile, services);
      sendJSON(res, 201, newService);
      return;
    }

    if (pathname.startsWith('/api/services/') && req.method === 'PUT') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор услуги' });
        return;
      }

      const body = await readBody(req);
      const payload = JSON.parse(body || '{}');
      const groups = readJSON(groupsFile, []);

      const services = readJSON(servicesFile, []);
      const idx = services.findIndex((s) => s.id === id);
      if (idx === -1) {
        sendJSON(res, 404, { error: 'Услуга не найдена' });
        return;
      }

      const draft = {
        ...services[idx],
        ...payload,
        name: payload.name !== undefined ? String(payload.name).trim() : services[idx].name,
        description:
          payload.description !== undefined
            ? String(payload.description).trim()
            : services[idx].description,
        price: payload.price !== undefined ? Number(payload.price) : services[idx].price,
        duration: payload.duration !== undefined ? Number(payload.duration) : services[idx].duration,
        groupId:
          payload.groupId !== undefined
            ? payload.groupId === null || payload.groupId === ''
              ? null
              : Number(payload.groupId)
            : services[idx].groupId
      };

      const error = validateServicePayload(draft, groups);
      if (error) {
        sendJSON(res, 400, { error });
        return;
      }

      services[idx] = draft;
      writeJSON(servicesFile, services);
      sendJSON(res, 200, draft);
      return;
    }

    if (pathname.startsWith('/api/services/') && req.method === 'DELETE') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор услуги' });
        return;
      }

      const services = readJSON(servicesFile, []);
      const nextServices = services.filter((s) => s.id !== id);
      if (nextServices.length === services.length) {
        sendJSON(res, 404, { error: 'Услуга не найдена' });
        return;
      }

      writeJSON(servicesFile, nextServices);
      sendJSON(res, 200, { success: true });
      return;
    }

    if (pathname === '/api/availability' && req.method === 'GET') {
      const date = String(query.date ?? '').trim();
      if (!DATE_REGEX.test(date)) {
        sendJSON(res, 400, { error: 'Укажите дату в формате ГГГГ-ММ-ДД' });
        return;
      }

      const services = readJSON(servicesFile, []);
      const serviceId = query.serviceId ? Number(query.serviceId) : null;
      let duration = query.duration ? Number(query.duration) : null;
      let service = null;

      if (serviceId != null && !Number.isNaN(serviceId)) {
        service = services.find((item) => item.id === serviceId);
        if (!service) {
          sendJSON(res, 404, { error: 'Услуга не найдена' });
          return;
        }
        duration = duration ?? Number(service.duration ?? SLOT_STEP_MIN);
      }

      duration = duration ?? SLOT_STEP_MIN;
      if (!Number.isFinite(duration) || duration <= 0) {
        sendJSON(res, 400, { error: 'Укажите корректную длительность услуги' });
        return;
      }

      const masterId = query.masterId != null && query.masterId !== '' ? String(query.masterId).trim() : null;
      const bookings = readJSON(bookingsFile, []);
      const alignedDuration = Math.max(
        SLOT_STEP_MIN,
        Math.ceil(duration / SLOT_STEP_MIN) * SLOT_STEP_MIN
      );
      const slots = buildDailySlots({ date, duration: alignedDuration, masterId, bookings });

      sendJSON(res, 200, {
        slots,
        meta: {
          slotStep: SLOT_STEP_MIN,
          serviceId: service?.id ?? null,
          serviceDuration: alignedDuration,
          businessHours: {
            open: BUSINESS_OPEN_TIME,
            close: BUSINESS_CLOSE_TIME
          }
        }
      });
      return;
    }

    if (pathname === '/api/bookings' && req.method === 'GET') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }

      const bookings = readJSON(bookingsFile, []);
      const { date, masterId, serviceId, status } = query;
      const filtered = bookings.filter((booking) => {
        if (date && booking.date !== date) {
          return false;
        }
        if (masterId && String(booking.masterId ?? '') !== String(masterId)) {
          return false;
        }
        if (serviceId && String(booking.serviceId) !== String(serviceId)) {
          return false;
        }
        if (status && booking.status !== status) {
          return false;
        }
        return true;
      });

      sendJSON(res, 200, filtered);
      return;
    }

    if (pathname === '/api/bookings' && req.method === 'POST') {
      const body = await readBody(req);
      const payload = JSON.parse(body || '{}');
      const services = readJSON(servicesFile, []);

      const error = validateBookingPayload(payload, services);
      if (error) {
        sendJSON(res, 400, { error });
        return;
      }

      const service = services.find((item) => item.id === Number(payload.serviceId));
      const bookings = readJSON(bookingsFile, []);

      const startMinutes = timeToMinutes(payload.startTime);
      const durationMinutes = alignDurationMinutes(
        Number(payload.duration ?? service.duration ?? SLOT_STEP_MIN)
      );
      if (!Number.isFinite(durationMinutes)) {
        sendJSON(res, 400, { error: 'Длительность должна быть положительной' });
        return;
      }
      const endMinutes = startMinutes + durationMinutes;

      const overlap = bookings.some((booking) => {
        if (booking.date !== payload.date) {
          return false;
        }
        if (String(booking.masterId ?? '') !== String(payload.masterId ?? '')) {
          return false;
        }
        const existingStart = timeToMinutes(booking.startTime);
        const existingDuration = alignDurationMinutes(Number(booking.duration ?? SLOT_STEP_MIN));
        const existingEnd = existingStart + existingDuration;
        return Math.max(existingStart, startMinutes) < Math.min(existingEnd, endMinutes);
      });

      if (overlap) {
        sendJSON(res, 409, { error: 'Слот уже занят, выберите другое время' });
        return;
      }

      const nowIso = new Date().toISOString();
      const newBooking = {
        id: Date.now(),
        createdAt: nowIso,
        updatedAt: nowIso,
        status: 'pending',
        clientName: String(payload.clientName).trim(),
        clientPhone: String(payload.clientPhone).trim(),
        notes: String(payload.notes ?? '').trim(),
        serviceId: Number(payload.serviceId),
        serviceName: service.name,
        serviceDuration: service.duration,
        servicePrice: service.price,
        masterId:
          payload.masterId == null || payload.masterId === ''
            ? null
            : String(payload.masterId).trim(),
        date: payload.date,
        startTime: minutesToTime(startMinutes),
        duration: durationMinutes
      };

      bookings.push(newBooking);
      writeJSON(bookingsFile, bookings);
      sendJSON(res, 201, newBooking);
      return;
    }

    if (pathname.startsWith('/api/bookings/') && req.method === 'PATCH') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }

      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор записи' });
        return;
      }

      const body = await readBody(req);
      const payload = JSON.parse(body || '{}');

      const bookings = readJSON(bookingsFile, []);
      const idx = bookings.findIndex((booking) => booking.id === id);
      if (idx === -1) {
        sendJSON(res, 404, { error: 'Запись не найдена' });
        return;
      }

      const draft = { ...bookings[idx] };
      if (payload.status) {
        draft.status = String(payload.status).trim();
      }

      if (payload.notes !== undefined) {
        draft.notes = String(payload.notes).trim();
      }

      if (payload.date) {
        if (!DATE_REGEX.test(payload.date)) {
          sendJSON(res, 400, { error: 'Неверный формат даты' });
          return;
        }
        draft.date = payload.date;
      }

      if (payload.startTime || payload.duration) {
        const servicesData = readJSON(servicesFile, []);
        const service = servicesData.find((item) => item.id === draft.serviceId);
        const nextStart = payload.startTime ? timeToMinutes(payload.startTime) : timeToMinutes(draft.startTime);
        const nextDuration = alignDurationMinutes(
          Number(payload.duration ?? draft.duration ?? service?.duration ?? SLOT_STEP_MIN)
        );

        if (!Number.isFinite(nextStart) || nextStart % SLOT_STEP_MIN !== 0) {
          sendJSON(res, 400, { error: `Время должно соответствовать шагу ${SLOT_STEP_MIN} минут` });
          return;
        }

        if (!Number.isFinite(nextDuration)) {
          sendJSON(res, 400, { error: 'Длительность должна быть положительной' });
          return;
        }

        const nextEnd = nextStart + nextDuration;
        const bookingsList = bookings.filter((booking) => booking.id !== id);
        const overlap = bookingsList.some((booking) => {
          if (booking.date !== draft.date) {
            return false;
          }
          if (String(booking.masterId ?? '') !== String(draft.masterId ?? '')) {
            return false;
          }
          const existingStart = timeToMinutes(booking.startTime);
          const existingDuration = alignDurationMinutes(Number(booking.duration ?? SLOT_STEP_MIN));
          const existingEnd = existingStart + existingDuration;
          return Math.max(existingStart, nextStart) < Math.min(existingEnd, nextEnd);
        });

        if (overlap) {
          sendJSON(res, 409, { error: 'Слот уже занят, выберите другое время' });
          return;
        }

        draft.startTime = minutesToTime(nextStart);
        draft.duration = nextDuration;
      }

      draft.updatedAt = new Date().toISOString();
      bookings[idx] = draft;
      writeJSON(bookingsFile, bookings);
      sendJSON(res, 200, draft);
      return;
    }

    if (pathname.startsWith('/api/bookings/') && req.method === 'DELETE') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }

      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор записи' });
        return;
      }

      const bookings = readJSON(bookingsFile, []);
      const nextBookings = bookings.filter((booking) => booking.id !== id);
      if (nextBookings.length === bookings.length) {
        sendJSON(res, 404, { error: 'Запись не найдена' });
        return;
      }

      writeJSON(bookingsFile, nextBookings);
      sendJSON(res, 200, { success: true });
      return;
    }

    if (pathname === '/' || pathname === '/client' || pathname === '/client/') {
      const html = readFileSync(join(__dirname, 'public', 'client.html'), 'utf-8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
      return;
    }

    // Telegram WebApp auth — verifies initData and sets signed cookie tg_id
    if (pathname === '/auth/telegram' && (req.method === 'POST' || req.method === 'GET')) {
      if (!TELEGRAM_BOT_TOKEN) { sendJSON(res, 400, { error: 'TELEGRAM_BOT_TOKEN not set' }); return; }
      const input = req.method === 'GET' ? (query.initData || query.init_data || '') : await readBody(req);
      let initData = '';
      try {
        if (req.method === 'GET') {
          initData = String(input || '').trim();
        } else {
          const p = JSON.parse(input||'{}');
          initData = String(p.initData || p.init_data || '').trim();
        }
      } catch { initData = ''; }
      if (!initData) { sendJSON(res, 400, { error: 'initData required' }); return; }

      // Parse initData (querystring format)
      const urlParams = new URLSearchParams(initData);
      const hash = urlParams.get('hash');
      urlParams.delete('hash');
      const dataCheckArr = [];
      for (const [k,v] of urlParams.entries()) dataCheckArr.push(`${k}=${v}`);
      dataCheckArr.sort();
      const dataCheckString = dataCheckArr.join('\n');

      // Calculate signature
      const secret = crypto.createHmac('sha256', 'WebAppData').update(TELEGRAM_BOT_TOKEN).digest();
      const calcHash = crypto.createHmac('sha256', secret).update(dataCheckString).digest('hex');
      if (calcHash !== hash) { sendJSON(res, 403, { error: 'invalid hash' }); return; }

      // Extract user
      let user = null;
      try { user = JSON.parse(urlParams.get('user')||'null'); } catch { user = null; }
      const id = Number(user?.id);
      if (!Number.isFinite(id)) { sendJSON(res, 400, { error: 'user.id missing' }); return; }

      // Set short-lived cookie (12h)
      setCookie(res, 'tg_id', String(id), { maxAge: 60*60*12 });
      sendJSON(res, 200, { ok: true, id });
      return;
    }

    if (pathname === '/admin' || pathname === '/admin/' || pathname.startsWith('/admin')) {
      const admins = readAdmins();
      const isAdmin = admins.some(a => a.id === ctx.telegramId);
      if (!isAdmin) {
        const deny = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>403</title><style>body{font-family:system-ui,-apple-system,Segoe UI,Inter,sans-serif;background:#f6f7fb;color:#111827;display:grid;place-items:center;height:100vh;margin:0}section{background:#fff;border:1px solid rgba(209,213,219,.5);border-radius:14px;padding:22px;max-width:720px;text-align:center;display:grid;gap:10px}</style><section><h1>Доступ ограничен</h1><p>Откройте админку из Telegram через команду <b>/admin</b> у бота или запустите мини‑приложение внутри Telegram — мы авторизуем вас автоматически.</p><p class="muted">Если вы уже в Telegram WebApp, попробуйте вернуться и открыть заново.</p></section>`;
        res.writeHead(403, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(deny);
        return;
      }
      const adminPrimary = join(__dirname, 'templates', 'admin.html');
      const adminFallback = join(__dirname, 'public', 'admin.html');
      const adminPath = existsSync(adminPrimary) ? adminPrimary : adminFallback;
      const html = readFileSync(adminPath, 'utf-8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
      return;
    }
    if (pathname === '/tg/webhook' && req.method === 'POST') {
      try {
        const raw = await readBody(req);
        console.log('TG UPDATE RAW:', raw);
        const update = JSON.parse(raw || '{}');
        console.log('TG UPDATE OBJ:', JSON.stringify(update));
        const msg = update.message || update.edited_message || (update.callback_query && update.callback_query.message) || null;
        const from = (update.message && update.message.from) || (update.edited_message && update.edited_message.from) || (update.callback_query && update.callback_query.from) || null;
        if (msg && from) {
          const chatId = msg.chat.id;
          const userId = from.id;
          const text = (update.message?.text || update.edited_message?.text || update.callback_query?.data || '').trim();
          if (/^\/start\b/.test(text)) {
            await tgSendMessage(chatId, '👋 Привет! Доступные команды:\n• /client — открыть клиентскую форму\n• /admin — админ-панель');
          } else if (/^\/client\b/.test(text)) {
            const url = `${PUBLIC_BASE_URL}/client`;
            await tgSendMessage(chatId, `🧾 <b>Клиентская форма</b>\n${url}`);
          } else if (/^\/admin\b/.test(text)) {
            const url = `${PUBLIC_BASE_URL}/admin?tg_id=${userId}`;
            await tgSendMessage(chatId, `🛠 <b>Админ-панель</b>\n${url}`);
          } else {
            await tgSendMessage(chatId, 'Не знаю эту команду. Попробуйте /client или /admin');
          }
        }
        sendJSON(res, 200, { ok: true });
      } catch (e) {
        sendJSON(res, 200, { ok: true });
      }
      return;
    }

    if (pathname === '/tg/info' && req.method === 'GET') {
      sendJSON(res, 200, { baseUrl: PUBLIC_BASE_URL, botConfigured: Boolean(TELEGRAM_BOT_TOKEN) });
      return;
    }

    // Telegram webhook utilities
    if (pathname === '/tg/getWebhookInfo' && req.method === 'GET') {
      if (!TG_API) { sendJSON(res, 400, { error: 'TELEGRAM_BOT_TOKEN not set' }); return; }
      try {
        const r = await fetch(`${TG_API}/getWebhookInfo`);
        const j = await r.json();
        sendJSON(res, 200, j);
      } catch (e) {
        sendJSON(res, 500, { error: String(e.message||e) });
      }
      return;
    }

    if (pathname === '/tg/setWebhook' && req.method === 'GET') {
      if (!TG_API) { sendJSON(res, 400, { error: 'TELEGRAM_BOT_TOKEN not set' }); return; }
      const url = `${PUBLIC_BASE_URL}/tg/webhook`;
      try {
        const r = await fetch(`${TG_API}/setWebhook`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }) });
        const j = await r.json();
        sendJSON(res, 200, { requestedUrl: url, ...j });
      } catch (e) {
        sendJSON(res, 500, { error: String(e.message||e) });
      }
      return;
    }

    if (pathname === '/tg/deleteWebhook' && req.method === 'GET') {
      if (!TG_API) { sendJSON(res, 400, { error: 'TELEGRAM_BOT_TOKEN not set' }); return; }
      try {
        const r = await fetch(`${TG_API}/deleteWebhook`, { method: 'POST' });
        const j = await r.json();
        sendJSON(res, 200, j);
      } catch (e) {
        sendJSON(res, 500, { error: String(e.message||e) });
      }
      return;
    }

    if (pathname === '/tg/test' && req.method === 'GET') {
      if (!TG_API) { sendJSON(res, 400, { error: 'TELEGRAM_BOT_TOKEN not set' }); return; }
      const chatId = query.chat_id || query.chatId;
      if (!chatId) { sendJSON(res, 400, { error: 'chat_id required' }); return; }
      await tgSendMessage(chatId, `Test OK: ${new Date().toISOString()}`);
      sendJSON(res, 200, { ok: true });
      return;
    }

    // ===== MASTERS API =====
    if (pathname === '/api/masters' && req.method === 'GET') {
      const masters = readJSON(mastersFile, []);
      sendJSON(res, 200, masters);
      return;
    }

    if (pathname === '/api/masters' && req.method === 'POST') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const body = await readBody(req);
      const payload = JSON.parse(body || '{}');

      const name = String(payload.name ?? '').trim();
      if (!name) {
        sendJSON(res, 400, { error: 'Имя мастера обязательно' });
        return;
      }

      const masters = readJSON(mastersFile, []);
      const newMaster = {
        id: Date.now(),
        name,
        specialties: Array.isArray(payload.specialties) ? payload.specialties.map(s => String(s)) : [],
        photoUrl: payload.photoUrl ? String(payload.photoUrl) : null,
        description: String(payload.description ?? ''),
        schedule: payload.schedule ?? null,
        serviceIds: Array.isArray(payload.serviceIds) ? payload.serviceIds.map(n => Number(n)).filter(Number.isFinite) : []
      };

      masters.push(newMaster);
      writeJSON(mastersFile, masters);
      sendJSON(res, 201, newMaster);
      return;
    }

    if (pathname.startsWith('/api/masters/') && req.method === 'PUT') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор мастера' });
        return;
      }

      const body = await readBody(req);
      const patch = JSON.parse(body || '{}');
      const masters = readJSON(mastersFile, []);
      const idx = masters.findIndex((m) => m.id === id);
      if (idx === -1) {
        sendJSON(res, 404, { error: 'Мастер не найден' });
        return;
      }

      const current = masters[idx];
      const next = {
        ...current,
        ...patch,
        name: patch.name !== undefined ? String(patch.name).trim() : current.name,
        specialties: patch.specialties !== undefined ? (Array.isArray(patch.specialties) ? patch.specialties.map(String) : current.specialties) : current.specialties,
        photoUrl: patch.photoUrl !== undefined ? (patch.photoUrl ? String(patch.photoUrl) : null) : current.photoUrl,
        description: patch.description !== undefined ? String(patch.description) : current.description,
        schedule: patch.schedule !== undefined ? patch.schedule : current.schedule,
        serviceIds: patch.serviceIds !== undefined ? (Array.isArray(patch.serviceIds) ? patch.serviceIds.map(n => Number(n)).filter(Number.isFinite) : current.serviceIds) : current.serviceIds
      };

      if (!next.name) {
        sendJSON(res, 400, { error: 'Имя мастера обязательно' });
        return;
      }

      masters[idx] = next;
      writeJSON(mastersFile, masters);
      sendJSON(res, 200, next);
      return;
    }

    if (pathname.startsWith('/api/masters/') && req.method === 'DELETE') {
      if (!ensureAuthorized(ctx, res, ['admin'])) {
        return;
      }
      const id = parseId(pathname);
      if (!id) {
        sendJSON(res, 400, { error: 'Некорректный идентификатор мастера' });
        return;
      }

      const masters = readJSON(mastersFile, []);
      const nextMasters = masters.filter((m) => m.id !== id);
      if (nextMasters.length === masters.length) {
        sendJSON(res, 404, { error: 'Мастер не найден' });
        return;
      }

      writeJSON(mastersFile, nextMasters);
      sendJSON(res, 200, { success: true });
      return;
    }

    // === Google Sheets integration ===
    if (pathname === '/api/gs/url' && req.method === 'GET') {
      const url = `https://docs.google.com/spreadsheets/d/${GOOGLE_SHEET_ID}/edit`;
      sendJSON(res, 200, { url, sheetId: GOOGLE_SHEET_ID });
      return;
    }

    if (pathname === '/api/gs/export' && req.method === 'POST') {
      if (!ensureAuthorized(ctx, res, ['admin'])) return;
      try {
        const groups = readJSON(groupsFile, []);
        const services = readJSON(servicesFile, []);
        const admins = readJSON(adminsFile, []);
        const masters = readJSON(mastersFile, []);
        const bookings = readJSON(bookingsFile, []);

        const groupsValues = [['id','name'], ...groups.map(g => [g.id, g.name])];
        const servicesValues = [['id','name','description','price','duration','groupId'], ...services.map(s => [s.id, s.name, s.description, s.price, s.duration, s.groupId ?? ''])];
        const adminsValues = [['id','username','displayName','role'], ...admins.map(a => [a.id, a.username, a.displayName||'', a.role])];
        const mastersValues = [['id','name','specialties','photoUrl','description','schedule_json','serviceIds'], ...masters.map(m => [m.id, m.name, toCsvList(m.specialties||[]), m.photoUrl||'', m.description||'', JSON.stringify(m.schedule||null), toCsvList(m.serviceIds||[])])];
        const bookingsValues = [['id','createdAt','updatedAt','status','clientName','clientPhone','notes','serviceId','serviceName','serviceDuration','servicePrice','masterId','date','startTime','duration'], ...bookings.map(b => [b.id,b.createdAt,b.updatedAt,b.status,b.clientName,b.clientPhone||'',b.notes||'',b.serviceId,b.serviceName||'',b.serviceDuration||'',b.servicePrice||'',b.masterId??'',b.date,b.startTime,b.duration])];

        await sheetsValuesClear(GOOGLE_SHEET_ID, 'Groups!A:Z');
        await sheetsValuesUpdate(GOOGLE_SHEET_ID, 'Groups!A1', groupsValues);
        await sheetsValuesClear(GOOGLE_SHEET_ID, 'Services!A:Z');
        await sheetsValuesUpdate(GOOGLE_SHEET_ID, 'Services!A1', servicesValues);
        await sheetsValuesClear(GOOGLE_SHEET_ID, 'Admins!A:Z');
        await sheetsValuesUpdate(GOOGLE_SHEET_ID, 'Admins!A1', adminsValues);
        await sheetsValuesClear(GOOGLE_SHEET_ID, 'Masters!A:Z');
        await sheetsValuesUpdate(GOOGLE_SHEET_ID, 'Masters!A1', mastersValues);
        await sheetsValuesClear(GOOGLE_SHEET_ID, 'Bookings!A:Z');
        await sheetsValuesUpdate(GOOGLE_SHEET_ID, 'Bookings!A1', bookingsValues);

        sendJSON(res, 200, { status: 'ok', updated: 'Sheets updated' });
      } catch (e) {
        console.error(e);
        sendJSON(res, 500, { error: String(e.message || e) });
      }
      return;
    }

    if (pathname === '/api/gs/import' && req.method === 'POST') {
      if (!ensureAuthorized(ctx, res, ['admin'])) return;
      try {
        const groupsResp = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Groups!A1:Z');
        const servicesResp = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Services!A1:Z');
        const adminsResp = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Admins!A1:Z');
        const mastersResp = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Masters!A1:Z');
        const bookingsResp = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Bookings!A1:Z');

        function rowsToObjects(values, headersExpected) {
          const rows = values?.values || [];
          if (rows.length <= 1) return [];
          const headers = rows[0];
          const idx = Object.fromEntries(headers.map((h,i)=>[h,i]));
          return rows.slice(1).filter(r=>r.length>0).map(r=>{
            const obj = {};
            headersExpected.forEach((h)=>{ obj[h] = r[idx[h]] ?? ''; });
            return obj;
          });
        }

        const groups = rowsToObjects(groupsResp, ['id','name']).map(r=>({ id: toNum(r.id) || Date.now(), name: String(r.name||'').trim() })).filter(g=>g.name);
        writeJSON(groupsFile, groups);

        const services = rowsToObjects(servicesResp, ['id','name','description','price','duration','groupId']).map(r=>({ id: toNum(r.id) || Date.now(), name: String(r.name||'').trim(), description: String(r.description||'').trim(), price: Number(r.price)||0, duration: Number(r.duration)||30, groupId: r.groupId===''?null:toNum(r.groupId) }));
        writeJSON(servicesFile, services);

        const admins = rowsToObjects(adminsResp, ['id','username','displayName','role']).map(r=>({ id: Number(r.id)||0, username: String(r.username||'').replace(/^@/,''), displayName: r.displayName||'', role: r.role==='owner'?'owner':'admin' })).filter(a=>a.id>0 && a.username);
        writeJSON(adminsFile, admins.length?admins:readJSON(adminsFile, []));

        const masters = rowsToObjects(mastersResp, ['id','name','specialties','photoUrl','description','schedule_json','serviceIds']).map(r=>({ id: toNum(r.id)||Date.now(), name: String(r.name||'').trim(), specialties: String(r.specialties||'').split(',').map(s=>s.trim()).filter(Boolean), photoUrl: r.photoUrl||null, description: r.description||'', schedule: (()=>{ try { return r.schedule_json?JSON.parse(r.schedule_json):null; } catch { return null; } })(), serviceIds: String(r.serviceIds||'').split(',').map(s=>toNum(s)).filter(Number.isFinite) }));
        writeJSON(mastersFile, masters);

        const bookings = rowsToObjects(bookingsResp, ['id','createdAt','updatedAt','status','clientName','clientPhone','notes','serviceId','serviceName','serviceDuration','servicePrice','masterId','date','startTime','duration']).map(r=>({ id: toNum(r.id)||Date.now(), createdAt: r.createdAt||new Date().toISOString(), updatedAt: r.updatedAt||r.createdAt||new Date().toISOString(), status: r.status||'pending', clientName: r.clientName||'', clientPhone: r.clientPhone||'', notes: r.notes||'', serviceId: Number(r.serviceId)||0, serviceName: r.serviceName||'', serviceDuration: Number(r.serviceDuration)||null, servicePrice: Number(r.servicePrice)||null, masterId: r.masterId===''?null:String(r.masterId), date: r.date||'', startTime: r.startTime||'', duration: Number(r.duration)||null }));
        writeJSON(bookingsFile, bookings);

        sendJSON(res, 200, { status: 'ok', imported: { groups: groups.length, services: services.length, admins: admins.length, masters: masters.length, bookings: bookings.length } });
      } catch (e) {
        console.error(e);
        sendJSON(res, 500, { error: String(e.message || e) });
      }
      return;
    }

        // === Backup ZIP (export) ===
    if (pathname === '/api/backup/export' && req.method === 'GET') {
      if (!ensureAuthorized(ctx, res, ['admin'])) return;
      try {
        const AdmZip = (await import('adm-zip')).default;
        const zip = new AdmZip();
        zip.addFile('groups.json', Buffer.from(JSON.stringify(readJSON(groupsFile, []), null, 2)));
        zip.addFile('services.json', Buffer.from(JSON.stringify(readJSON(servicesFile, []), null, 2)));
        zip.addFile('admins.json', Buffer.from(JSON.stringify(readJSON(adminsFile, []), null, 2)));
        zip.addFile('masters.json', Buffer.from(JSON.stringify(readJSON(mastersFile, []), null, 2)));
        zip.addFile('bookings.json', Buffer.from(JSON.stringify(readJSON(bookingsFile, []), null, 2)));
        zip.addFile('manifest.json', Buffer.from(JSON.stringify({ createdAt: new Date().toISOString(), version: 1 }, null, 2)));
        const name = makeBackupName();
        const buf = zip.toBuffer();
        res.writeHead(200, { 'Content-Type': 'application/zip', 'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(name)}` });
        res.end(buf);
      } catch (e) {
        console.error(e);
        sendJSON(res, 500, { error: String(e.message || e) });
      }
      return;
    }

    // === Backup ZIP (import) ===
    if (pathname === '/api/backup/import' && req.method === 'POST') {
      if (!ensureAuthorized(ctx, res, ['admin'])) return;
      try {
        const Busboy = (await import('busboy')).default;
        const bb = Busboy({ headers: req.headers });
        let zipBuffer = Buffer.alloc(0);
        let received = false;
        await new Promise((resolve, reject) => {
          bb.on('file', (_name, stream) => {
            received = true;
            stream.on('data', (chunk) => { zipBuffer = Buffer.concat([zipBuffer, chunk]); });
            stream.on('error', reject);
          });
          bb.on('error', reject);
          bb.on('finish', resolve);
          req.pipe(bb);
        });
        if (!received || !zipBuffer.length) { sendJSON(res, 400, { error: 'Файл не получен' }); return; }
        const AdmZip = (await import('adm-zip')).default;
        const zip = new AdmZip(zipBuffer);
        const entries = Object.fromEntries(zip.getEntries().map(e => [e.entryName, e]));
        function readJsonEntry(name) {
          const e = entries[name]; if (!e) return null;
          try { return JSON.parse(e.getData().toString('utf-8')); } catch { return null; }
        }
        const groups = readJsonEntry('groups.json');
        const services = readJsonEntry('services.json');
        const admins = readJsonEntry('admins.json');
        const masters = readJsonEntry('masters.json');
        const bookings = readJsonEntry('bookings.json');
        if (groups) writeJSON(groupsFile, groups);
        if (services) writeJSON(servicesFile, services);
        if (admins) writeJSON(adminsFile, admins);
        if (masters) writeJSON(mastersFile, masters);
        if (bookings) writeJSON(bookingsFile, bookings);
        const imported = {
          groups: Array.isArray(groups) ? groups.length : 0,
          services: Array.isArray(services) ? services.length : 0,
          admins: Array.isArray(admins) ? admins.length : 0,
          masters: Array.isArray(masters) ? masters.length : 0,
          bookings: Array.isArray(bookings) ? bookings.length : 0
        };
        sendJSON(res, 200, { status: 'ok', imported });
      } catch (e) {
        console.error(e);
        sendJSON(res, 500, { error: String(e.message || e) });
      }
      return;
    }

    sendJSON(res, 404, { error: 'Файл не найден' });
  } catch (error) {
    console.error('Необработанная ошибка сервера:', error);
    sendJSON(res, 500, { error: 'Внутренняя ошибка сервера' });
  }
});

const PORT = process.env.PORT || 8080;
server.listen(PORT, () => console.log(`✅ Сервер запущен на порту ${PORT}`));
EOF

#
# --- client.html ---
cat <<'EOF' > public/client.html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Запись в салон — Beauty Appointments</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    :root {
      color-scheme: light;
      font-family: 'SF Pro Display', 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    }

    body {
      margin: 0;
      padding: 32px 16px 48px;
      background: linear-gradient(180deg, #f6f7fb 0%, #f0f3f8 45%, #eef1f7 100%);
      color: #111827;
      min-height: 100vh;
    }

    main {
      max-width: 720px;
      margin: 0 auto;
      display: grid;
      gap: 28px;
    }

    header {
      text-align: center;
      display: grid;
      gap: 12px;
    }

    header h1 {
      margin: 0;
      font-size: clamp(28px, 5vw, 38px);
      font-weight: 700;
      letter-spacing: -0.02em;
    }

    header p {
      margin: 0 auto;
      max-width: 520px;
      color: #4b5563;
      font-size: 16px;
      line-height: 1.5;
    }

    section {
      background: rgba(255, 255, 255, 0.92);
      backdrop-filter: blur(14px);
      border-radius: 20px;
      padding: 24px;
      box-shadow: 0 35px 60px -40px rgba(15, 23, 42, 0.35);
      border: 1px solid rgba(209, 213, 219, 0.4);
      display: grid;
      gap: 18px;
    }

    section h2 {
      margin: 0;
      font-size: 22px;
      font-weight: 600;
    }

    .form-grid {
      display: grid;
      gap: 16px;
    }

    label {
      display: grid;
      gap: 6px;
      font-size: 14px;
      color: #4b5563;
    }

    input,
    select,
    textarea {
      border: 1px solid rgba(148, 163, 184, 0.45);
      border-radius: 12px;
      padding: 12px 14px;
      font-size: 15px;
      font-family: inherit;
      background: rgba(255, 255, 255, 0.95);
      transition: border-color 0.2s ease, box-shadow 0.2s ease;
    }

    input:focus,
    select:focus,
    textarea:focus {
      outline: none;
      border-color: rgba(99, 102, 241, 0.9);
      box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.18);
      background: #fff;
    }

    textarea {
      min-height: 90px;
      resize: vertical;
    }

    .pill-select {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
    }

    .pill-button {
      padding: 10px 18px;
      border-radius: 999px;
      border: 1px solid rgba(148, 163, 184, 0.45);
      background: rgba(255, 255, 255, 0.9);
      cursor: pointer;
      font-size: 14px;
      transition: transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease;
    }

    .pill-button:hover {
      transform: translateY(-2px);
      box-shadow: 0 18px 32px -24px rgba(15, 23, 42, 0.45);
    }

    .pill-button.active {
      background: linear-gradient(130deg, #7cb9ff, #007aff);
      color: #fff;
      border-color: transparent;
      box-shadow: 0 20px 30px -22px rgba(0, 122, 255, 0.55);
    }

    .slot-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
      gap: 12px;
    }

    .slot-button {
      padding: 12px;
      border-radius: 14px;
      border: 1px solid rgba(148, 163, 184, 0.4);
      background: rgba(255, 255, 255, 0.92);
      cursor: pointer;
      font-size: 15px;
      font-weight: 500;
      display: grid;
      gap: 4px;
      justify-items: center;
      transition: transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease;
    }

    .slot-button:hover {
      transform: translateY(-2px);
      box-shadow: 0 20px 34px -26px rgba(15, 23, 42, 0.38);
    }

    .slot-button.selected {
      border-color: transparent;
      background: linear-gradient(130deg, #4ade80, #34c759);
      color: #fff;
      box-shadow: 0 24px 32px -24px rgba(52, 199, 89, 0.55);
    }

    .slot-button[disabled] {
      cursor: not-allowed;
      opacity: 0.45;
      transform: none;
      box-shadow: none;
    }

    .muted {
      color: #6b7280;
      font-size: 14px;
    }

    .muted.error {
      color: #ef4444;
    }

    .submit-btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 14px 22px;
      border-radius: 16px;
      border: none;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      background: linear-gradient(135deg, #5ec5ff, #007aff);
      color: #fff;
      box-shadow: 0 24px 40px -28px rgba(0, 122, 255, 0.55);
      transition: transform 0.2s ease, box-shadow 0.2s ease;
    }

    .submit-btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 28px 46px -24px rgba(0, 122, 255, 0.55);
    }

    .summary-card {
      border-radius: 18px;
      border: 1px solid rgba(209, 213, 219, 0.5);
      background: rgba(249, 250, 251, 0.9);
      padding: 16px 18px;
      display: grid;
      gap: 6px;
      font-size: 15px;
      color: #374151;
    }

  .banner {
    position: fixed;
    bottom: 24px;
    left: 50%;
    transform: translateX(-50%);
    padding: 14px 22px;
    border-radius: 14px;
    background: linear-gradient(135deg, rgba(94, 197, 255, 0.95), rgba(0, 122, 255, 0.95));
    color: #fff;
    font-weight: 600;
    box-shadow: 0 32px 48px -32px rgba(0, 122, 255, 0.55);
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.2s ease, transform 0.2s ease;
  }

    .banner.show {
      opacity: 1;
      transform: translate(-50%, -6px);
    }

  .banner.error {
    background: linear-gradient(135deg, rgba(255, 95, 95, 0.95), rgba(244, 63, 94, 0.95));
    box-shadow: 0 32px 48px -32px rgba(244, 63, 94, 0.6);
  }

    @media (max-width: 600px) {
      section {
        padding: 20px;
      }

      .slot-grid {
        grid-template-columns: repeat(auto-fill, minmax(110px, 1fr));
      }

      .submit-btn {
        width: 100%;
      }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Запишитесь в любимый салон</h1>
      <p>Выберите услугу, удобное время и подтвердите запись буквально за минуту. Мы напомним вам о визите в Telegram.</p>
    </header>

    <form id="bookingForm" class="form-grid">
      <section>
        <h2>Контакты</h2>
        <div class="form-grid">
          <label>
            Как к вам обращаться
            <input type="text" id="clientName" placeholder="Имя и фамилия" required />
          </label>
          <label>
            Телефон
            <input type="tel" id="clientPhone" placeholder="+7 (999) 123-45-67" required />
          </label>
          <label>
            Комментарий для мастера (необязательно)
            <textarea id="clientNotes" placeholder="Например: хочу нежный пастельный оттенок"></textarea>
          </label>
        </div>
      </section>

      <section>
        <h2>Выбор услуги</h2>
        <label>
          Услуга
          <select id="serviceSelect" required>
            <option value="" disabled selected>Загружаю список…</option>
          </select>
        </label>
        <div class="summary-card" id="serviceSummary" hidden></div>
      </section>

      <section>
        <h2>Дата и специалист</h2>
        <div class="form-grid">
          <label>
            Дата визита
            <input type="date" id="dateInput" required />
          </label>
          <label>
            ID мастера (необязательно)
            <input type="text" id="masterInput" placeholder="Если хотите записаться к конкретному мастеру" />
          </label>
        </div>
        <p class="muted" id="availabilityHint">Выберите услугу и дату, чтобы увидеть свободные слоты.</p>
      </section>

      <section>
        <h2>Свободные слоты</h2>
        <div id="slotsContainer" class="slot-grid"></div>
        <p class="muted" id="slotsEmpty" hidden>На выбранный день пока нет свободных окон. Попробуйте другую дату.</p>
      </section>

      <section>
        <h2>Подтверждение</h2>
        <div class="summary-card" id="selectionSummary" hidden></div>
        <button type="submit" class="submit-btn">Подтвердить запись</button>
      </section>
    </form>
  </main>

  <div class="banner" id="banner" hidden></div>

  <script>
    document.addEventListener('DOMContentLoaded', () => {
      const bookingForm = document.getElementById('bookingForm');
      const serviceSelect = document.getElementById('serviceSelect');
      const serviceSummary = document.getElementById('serviceSummary');
      const dateInput = document.getElementById('dateInput');
      const masterInput = document.getElementById('masterInput');
      const slotsContainer = document.getElementById('slotsContainer');
      const slotsEmpty = document.getElementById('slotsEmpty');
      const selectionSummary = document.getElementById('selectionSummary');
      const banner = document.getElementById('banner');
      const availabilityHint = document.getElementById('availabilityHint');

      const clientNameInput = document.getElementById('clientName');
      const clientPhoneInput = document.getElementById('clientPhone');
      const clientNotesInput = document.getElementById('clientNotes');

      const state = {
        services: [],
        selectedServiceId: null,
        selectedSlot: null,
        availability: [],
        serviceDuration: null
      };

      const showBanner = (message, type = 'success') => {
        banner.textContent = message;
        banner.classList.toggle('error', type === 'error');
        banner.classList.add('show');
        banner.hidden = false;
        setTimeout(() => {
          banner.classList.remove('show');
          setTimeout(() => {
            banner.hidden = true;
          }, 180);
        }, 2400);
      };

      const formatCurrency = (value) =>
        new Intl.NumberFormat('ru-RU', { style: 'currency', currency: 'RUB', maximumFractionDigits: 0 }).format(value);

      const renderServiceSummary = () => {
        const service = state.services.find((item) => item.id === state.selectedServiceId);
        if (!service) {
          serviceSummary.hidden = true;
          serviceSummary.innerHTML = '';
          return;
        }

        state.serviceDuration = service.duration;
        serviceSummary.hidden = false;
        serviceSummary.innerHTML = `
          <strong>${service.name}</strong>
          <span>${service.description}</span>
          <span><strong>${formatCurrency(service.price)}</strong> · ${service.duration} мин</span>
        `;
      };

      const renderSelectionSummary = () => {
        const service = state.services.find((item) => item.id === state.selectedServiceId);
        if (!service || !state.selectedSlot || !dateInput.value) {
          selectionSummary.hidden = true;
          selectionSummary.innerHTML = '';
          return;
        }

        const date = new Date(dateInput.value);
        const formattedDate = date.toLocaleDateString('ru-RU', {
          weekday: 'long',
          day: 'numeric',
          month: 'long'
        });

        selectionSummary.hidden = false;
        selectionSummary.innerHTML = `
          <div><strong>${service.name}</strong></div>
          <div>${formattedDate}, ${state.selectedSlot.startTime}</div>
          <div>${formatCurrency(service.price)}, длительность ${service.duration} мин</div>
        `;
      };

      const clearSlots = () => {
        slotsContainer.innerHTML = '';
        slotsEmpty.hidden = true;
        state.selectedSlot = null;
        renderSelectionSummary();
      };

      const renderSlots = () => {
        clearSlots();

        const availableSlots = state.availability.filter((slot) => slot.available);
        if (!availableSlots.length) {
          slotsEmpty.hidden = false;
          return;
        }

        const fragment = document.createDocumentFragment();
        availableSlots.forEach((slot) => {
          const button = document.createElement('button');
          button.type = 'button';
          button.className = 'slot-button';
          button.dataset.start = slot.startTime;
          button.textContent = slot.startTime;

          button.addEventListener('click', () => {
            state.selectedSlot = slot;
            document.querySelectorAll('.slot-button').forEach((el) => el.classList.remove('selected'));
            button.classList.add('selected');
            renderSelectionSummary();
          });

          fragment.appendChild(button);
        });

        slotsContainer.appendChild(fragment);
      };

      const fetchAvailability = async () => {
        if (!state.selectedServiceId || !dateInput.value) {
          availabilityHint.textContent = 'Выберите услугу и дату, чтобы увидеть свободные слоты.';
          availabilityHint.classList.remove('error');
          clearSlots();
          return;
        }

        availabilityHint.textContent = 'Проверяю доступные окна…';
        const params = new URLSearchParams({
          serviceId: state.selectedServiceId,
          date: dateInput.value
        });

        if (masterInput.value.trim()) {
          params.set('masterId', masterInput.value.trim());
        }

        try {
          const response = await fetch(`/api/availability?${params.toString()}`);
          if (!response.ok) {
            const payload = await response.json().catch(() => ({ error: 'Не удалось получить слоты' }));
            availabilityHint.textContent = payload.error || 'Не удалось получить слоты';
            availabilityHint.classList.add('error');
            clearSlots();
            return;
          }

          const data = await response.json();
          state.availability = Array.isArray(data.slots) ? data.slots : [];
          state.serviceDuration = data.meta?.serviceDuration ?? state.serviceDuration;
          availabilityHint.textContent = `Доступно свободных окон: ${state.availability.filter((slot) => slot.available).length}`;
          availabilityHint.classList.remove('error');
          renderSlots();
        } catch (error) {
          console.error(error);
          availabilityHint.textContent = 'Не удалось получить слоты';
          availabilityHint.classList.add('error');
          clearSlots();
        }
      };

      const loadServices = async () => {
        try {
          const response = await fetch('/api/services');
          if (!response.ok) {
            throw new Error('services request failed');
          }
          const services = await response.json();
          state.services = services;

          if (!services.length) {
            serviceSelect.innerHTML = '<option value="" disabled selected>Нет доступных услуг</option>';
            serviceSelect.disabled = true;
            return;
          }

          const options = ['<option value="" disabled selected>Выберите услугу</option>'];
          services.forEach((service) => {
            options.push(
              `<option value="${service.id}">${service.name} · ${service.duration} мин · ${formatCurrency(service.price)}</option>`
            );
          });
          serviceSelect.innerHTML = options.join('');
          serviceSelect.disabled = false;
        } catch (error) {
          console.error(error);
          serviceSelect.innerHTML = '<option value="" disabled selected>Не удалось загрузить услуги</option>';
          serviceSelect.disabled = true;
        }
      };

      const initDate = () => {
        const today = new Date();
        const iso = today.toISOString().split('T')[0];
        dateInput.min = iso;
        dateInput.value = iso;
      };

      serviceSelect.addEventListener('change', (event) => {
        state.selectedServiceId = Number(event.target.value);
        renderServiceSummary();
        fetchAvailability();
      });

      dateInput.addEventListener('change', fetchAvailability);
      masterInput.addEventListener('change', fetchAvailability);

      bookingForm.addEventListener('submit', async (event) => {
        event.preventDefault();

        if (!state.selectedServiceId) {
          showBanner('Выберите услугу', 'error');
          return;
        }

        if (!state.selectedSlot) {
          showBanner('Выберите свободное время', 'error');
          return;
        }

        const payload = {
          clientName: clientNameInput.value.trim(),
          clientPhone: clientPhoneInput.value.trim(),
          notes: clientNotesInput.value.trim(),
          serviceId: state.selectedServiceId,
          date: dateInput.value,
          startTime: state.selectedSlot.startTime,
          duration: state.serviceDuration,
          masterId: masterInput.value.trim() || null
        };

        if (!payload.clientName || !payload.clientPhone) {
          showBanner('Заполните контакты', 'error');
          return;
        }

        try {
          const response = await fetch('/api/bookings', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
          });

          if (!response.ok) {
            const data = await response.json().catch(() => ({ error: 'Не удалось создать запись' }));
            showBanner(data.error || 'Не удалось создать запись', 'error');
            await fetchAvailability();
            return;
          }

          await response.json();
          showBanner('Запись подтверждена!');
          bookingForm.reset();
          initDate();
          state.selectedServiceId = null;
          state.selectedSlot = null;
          serviceSummary.hidden = true;
          selectionSummary.hidden = true;
          serviceSelect.selectedIndex = 0;
          fetchAvailability();
        } catch (error) {
          console.error(error);
          showBanner('Не удалось создать запись', 'error');
        }
      });

      initDate();
      loadServices().then(fetchAvailability);
    });
  </script>
</body>
</html>
EOF

# --- admin.html ---
# ADMIN UI template will be copied below
cp "$SCRIPT_DIR/templates/admin.html" public/admin.html

echo ">>> Установка зависимостей..."
npm install --omit=dev
npm install adm-zip busboy --omit=dev

echo ">>> Запуск сервера..."
npm start

 # --- admin.html ---
 cat <<'EOF' > public/admin.html
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Админка — Masters CRUD</title>
  <style>
    body{font-family:system-ui,-apple-system,'Segoe UI',Inter,sans-serif;margin:0;padding:24px;background:#f6f7fb;color:#111827}
    main{max-width:1000px;margin:0 auto;display:grid;gap:20px}
    section{background:#fff;border:1px solid rgba(209,213,219,.5);border-radius:16px;padding:18px;display:grid;gap:12px}
    label{display:grid;gap:6px;color:#4b5563;font-size:14px}
    input,select,textarea{border:1px solid rgba(148,163,184,.45);border-radius:10px;padding:10px 12px;font:inherit}
    table{width:100%;border-collapse:collapse}
    th,td{border-top:1px solid rgba(209,213,219,.6);padding:8px 10px;text-align:left;vertical-align:top}
    .primary-btn{background:#2563eb;color:#fff;border:none;border-radius:10px;padding:10px 14px;cursor:pointer}
    .secondary-btn{background:#e5e7eb;color:#111827;border:none;border-radius:10px;padding:8px 12px;cursor:pointer}
    .danger-btn{background:#ef4444;color:#fff;border:none;border-radius:10px;padding:8px 12px;cursor:pointer}
    .muted{color:#6b7280}
  </style>
</head>
<body>
<main>
  <h1>Админка — Мастера</h1>
  <section>
    <h2>Добавить мастера</h2>
    <form id="masterForm">
      <div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px">
        <label>Имя<input name="name" required placeholder="Анна Петрова"></label>
        <label>Специальности<input name="specialties" placeholder="бровист, визажист"></label>
        <label style="grid-column:1/3">Фото (URL)<input name="photoUrl" placeholder="https://.../photo.jpg"></label>
        <label style="grid-column:1/3">Описание<textarea name="description" rows="3"></textarea></label>
      </div>
      <div style="display:flex;gap:8px;align-items:center;margin-top:8px">
        <select id="masterServicesPicker"></select>
        <button type="button" class="secondary-btn" id="masterServicesAdd">Добавить услугу</button>
        <button type="button" class="secondary-btn" id="masterServicesRemove">Удалить выбранные</button>
      </div>
      <label style="margin-top:8px">Услуги мастера
        <select name="serviceIds" multiple size="6"></select>
      </label>
      <div style="margin-top:10px">
        <button class="primary-btn" type="submit">Добавить мастера</button>
      </div>
    </form>
  </section>

  <section>
    <h2>Список мастеров</h2>
    <table>
      <thead><tr><th>Имя</th><th>Спец-ть</th><th>Услуги</th><th></th></tr></thead>
      <tbody id="mastersTable"></tbody>
    </table>
  </section>
</main>
<script>
// Auto-auth via Telegram WebApp initData (if opened inside Telegram)
try{
  const tg = window.Telegram && window.Telegram.WebApp;
  if (tg && tg.initData) {
    fetch('/auth/telegram', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ initData: tg.initData }) })
      .then(()=>{/* cookie set */})
      .catch(()=>{});
  }
}catch(_){}
(async function(){
  const masterForm = document.getElementById('masterForm');
  const mastersTable = document.getElementById('mastersTable');
  const servicesPicker = document.getElementById('masterServicesPicker');
  const addBtn = document.getElementById('masterServicesAdd');
  const removeBtn = document.getElementById('masterServicesRemove');
  const servicesSelect = masterForm.querySelector('select[name="serviceIds"]');

  const state = { services: [], masters: [] };
  const api = (path, opts={}) => fetch(path, { headers: { 'Content-Type': 'application/json' }, ...opts });

  const loadServices = async()=>{
    const r = await api('/api/services');
    state.services = r.ok ? await r.json() : [];
    servicesSelect.innerHTML = state.services.map(s=>`<option value="${s.id}">${s.name} (${s.duration} мин)</option>`).join('');
    updatePicker();
  };

  function updatePicker(){
    const selected = new Set(Array.from(servicesSelect.selectedOptions).map(o=>Number(o.value)));
    const options = state.services.filter(s=>!selected.has(s.id)).map(s=>`<option value="${s.id}">${s.name} (${s.duration} мин)</option>`);
    servicesPicker.innerHTML = options.join('');
    servicesPicker.disabled = options.length===0;
  }

  addBtn.addEventListener('click',()=>{
    const val = servicesPicker.value; if(!val) return;
    const opt = Array.from(servicesSelect.options).find(o=>o.value===val);
    if(opt){ opt.selected = true; updatePicker(); }
  });
  removeBtn.addEventListener('click',()=>{
    const sel = Array.from(servicesSelect.selectedOptions); if(!sel.length) return;
    sel.forEach(o=>o.selected=false); updatePicker();
  });
  servicesSelect.addEventListener('change', updatePicker);

  const renderMasters = ()=>{
    mastersTable.innerHTML = '';
    if(!state.masters.length){ mastersTable.innerHTML = '<tr><td colspan="4" class="muted">Пока нет мастеров</td></tr>'; return; }
    state.masters.forEach(m=>{
      const tr = document.createElement('tr');
      const services = (m.serviceIds||[]).map(id=>state.services.find(s=>s.id===id)?.name).filter(Boolean).join(', ');
      tr.innerHTML = `<td>${m.name||''}</td><td>${(m.specialties||[]).join(', ')}</td><td>${services||'—'}</td><td><button data-id="${m.id}" class="danger-btn">Удалить</button></td>`;
      mastersTable.appendChild(tr);
    });
  };

  const loadMasters = async()=>{
    const r = await api('/api/masters');
    state.masters = r.ok ? await r.json() : [];
    renderMasters();
  };

  masterForm.addEventListener('submit', async (e)=>{
    e.preventDefault();
    const fd = new FormData(masterForm);
    const serviceIds = Array.from(servicesSelect.selectedOptions).map(o=>Number(o.value));
    const payload = {
      name: fd.get('name'),
      specialties: String(fd.get('specialties')||'').split(',').map(s=>s.trim()).filter(Boolean),
      photoUrl: fd.get('photoUrl')||null,
      description: fd.get('description')||'',
      schedule: null,
      serviceIds
    };
    const r = await api('/api/masters', { method: 'POST', body: JSON.stringify(payload) });
    if(!r.ok){ alert('Ошибка при добавлении мастера'); return; }
    const created = await r.json();
    state.masters.push(created);
    masterForm.reset();
    servicesSelect.selectedIndex = -1;
    updatePicker();
    renderMasters();
  });

  mastersTable.addEventListener('click', async (e)=>{
    const btn = e.target.closest('button.danger-btn'); if(!btn) return;
    const id = Number(btn.dataset.id); if(!id) return;
    const r = await api(`/api/masters/${id}`, { method: 'DELETE' });
    if(!r.ok){ alert('Ошибка удаления'); return; }
    state.masters = state.masters.filter(m=>m.id!==id);
    renderMasters();
  });

  await loadServices();
  await loadMasters();
})();
</script>
</body>
</html>
EOF