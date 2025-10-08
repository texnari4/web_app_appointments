#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> 🚀 Развёртывание мини-приложения (сервер + админка v13)..."

# --- Подготовка директорий ---
# mkdir -p app/data - создаётся автоматически при первом запуске, включить при первом деплое
mkdir -p app/public
mkdir -p app/templates

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
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync, readdirSync } from 'fs';
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
const contactsFile = join(DATA_DIR, 'contacts.json');

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || null;
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || 'https://beautyminiappappointments-production.up.railway.app').replace(/\/+$/,'');
const TG_API = TELEGRAM_BOT_TOKEN ? `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}` : null;
const TELEGRAM_BOT_USERNAME = process.env.TELEGRAM_BOT_USERNAME || null;

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
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  const hh = String(d.getHours()).padStart(2, '0');
  const mi = String(d.getMinutes()).padStart(2, '0');
  const ss = String(d.getSeconds()).padStart(2, '0');
  return `backup_${yyyy}-${mm}-${dd}_${hh}-${mi}-${ss}.zip`;
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
const DEFAULT_CONTACTS = [];

const DEFAULT_ADMINS = [
  {
    id: 486778995,
    username: 'mr_tenbit',
    displayName: 'mr_tenbit',
    role: 'owner'
  }
];

function ensureDataFile(file, fallback) {
  // 🔒 Persistency-first: only create the file if it does not exist.
  // Never overwrite existing content during deploy, even if empty or unreadable.
  if (!existsSync(file)) {
    try {
      writeFileSync(file, JSON.stringify(fallback, null, 2));
    } catch (e) {
      // As a last resort, attempt to create an empty JSON array/object
      try { writeFileSync(file, Array.isArray(fallback) ? '[]' : '{}'); } catch {}
    }
  }
}

ensureDataFile(groupsFile, DEFAULT_GROUPS);
ensureDataFile(servicesFile, DEFAULT_SERVICES);
ensureDataFile(bookingsFile, DEFAULT_BOOKINGS);
ensureDataFile(adminsFile, DEFAULT_ADMINS);
ensureDataFile(mastersFile, DEFAULT_MASTERS);
ensureDataFile(contactsFile, DEFAULT_CONTACTS);

// --- Cold-deploy restoration helpers ---
function restoreFromLocalBackupsIfMissing() {
  try {
    const bakDir = join(DATA_DIR, '_backup');
    const files = [groupsFile, servicesFile, adminsFile, mastersFile, bookingsFile, contactsFile];
    for (const fpath of files) {
      if (existsSync(fpath)) continue;
      try {
        const base = fpath.split('/').pop().replace(/\.json$/, '');
        const names = readdirSync(bakDir)
          .filter(n => n.startsWith(base + '.') && n.endsWith('.bak.json'))
          .sort();
        if (names.length) {
          const latest = names[names.length-1];
          const content = readFileSync(join(bakDir, latest));
          writeFileSync(fpath, content);
        }
      } catch {}
    }
  } catch {}
}

async function restoreFromGoogleSheetsIfEmpty() {
  if (!GOOGLE_SERVICE_ACCOUNT_JSON) return;
  try {
    const services = readJSON(servicesFile, []);
    const masters = readJSON(mastersFile, []);
    if ((services?.length ?? 0) === 0 && (masters?.length ?? 0) === 0) {
      const groupsResp    = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Groups!A1:Z');
      const servicesResp  = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Services!A1:Z');
      const adminsResp    = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Admins!A1:Z');
      const mastersResp   = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Masters!A1:Z');
      const bookingsResp  = await sheetsValuesGet(GOOGLE_SHEET_ID, 'Bookings!A1:Z');
      function rowsToObjects(values, headersExpected) {
        const rows = values?.values || [];
        if (rows.length <= 1) return [];
        const headers = rows[0];
        const idx = Object.fromEntries(headers.map((h,i)=>[h,i]));
        return rows.slice(1).filter(r=>r.length>0).map(r=>{
          const obj = {}; headersExpected.forEach((h)=>{ obj[h] = r[idx[h]] ?? ''; }); return obj;
        });
      }
      const groups = rowsToObjects(groupsResp, ['id','name']).map(r=>({ id: toNum(r.id)||Date.now(), name:String(r.name||'').trim() })).filter(g=>g.name);
      if (groups.length) writeJSON(groupsFile, groups);
      const servicesArr = rowsToObjects(servicesResp, ['id','name','description','price','duration','groupId']).map(r=>({ id: toNum(r.id)||Date.now(), name:String(r.name||'').trim(), description:String(r.description||'').trim(), price:Number(r.price)||0, duration:Number(r.duration)||30, groupId:r.groupId===''?null:toNum(r.groupId) }));
      if (servicesArr.length) writeJSON(servicesFile, servicesArr);
      const adminsArr = rowsToObjects(adminsResp, ['id','username','displayName','role']).map(r=>({ id:Number(r.id)||0, username:String(r.username||'').replace(/^@/,''), displayName:r.displayName||'', role:r.role==='owner'?'owner':'admin' })).filter(a=>a.id>0 && a.username);
      if (adminsArr.length) writeJSON(adminsFile, adminsArr);
      const mastersArr = rowsToObjects(mastersResp, ['id','name','specialties','photoUrl','description','schedule_json','serviceIds']).map(r=>({ id: toNum(r.id)||Date.now(), name:String(r.name||'').trim(), specialties:String(r.specialties||'').split(',').map(s=>s.trim()).filter(Boolean), photoUrl:r.photoUrl||null, description:r.description||'', schedule:(()=>{ try { return r.schedule_json?JSON.parse(r.schedule_json):null; } catch { return null; } })(), serviceIds:String(r.serviceIds||'').split(',').map(x=>toNum(x)).filter(Number.isFinite) }));
      if (mastersArr.length) writeJSON(mastersFile, mastersArr);
      const bookingsArr = rowsToObjects(bookingsResp, ['id','createdAt','updatedAt','status','clientName','clientPhone','notes','serviceId','serviceName','serviceDuration','servicePrice','masterId','date','startTime','duration']).map(r=>({ id: toNum(r.id)||Date.now(), createdAt:r.createdAt||new Date().toISOString(), updatedAt:r.updatedAt||r.createdAt||new Date().toISOString(), status:r.status||'pending', clientName:r.clientName||'', clientPhone:r.clientPhone||'', notes:r.notes||'', serviceId:Number(r.serviceId)||0, serviceName:r.serviceName||'', serviceDuration:Number(r.serviceDuration)||null, servicePrice:Number(r.servicePrice)||null, masterId:r.masterId===''?null:String(r.masterId), date:r.date||'', startTime:r.startTime||'', duration:Number(r.duration)||null }));
      if (bookingsArr.length) writeJSON(bookingsFile, bookingsArr);
    }
  } catch (e) {
    console.warn('Restore from Google Sheets failed:', e?.message||e);
  }
}

// --- Run restoration on boot ---
restoreFromLocalBackupsIfMissing();
await (async()=>{ try { await restoreFromGoogleSheetsIfEmpty(); } catch {} })();

function readJSON(file, fallback = []) {
  try {
    return JSON.parse(readFileSync(file, 'utf-8'));
  } catch (err) {
    console.error(`Ошибка чтения ${file}:`, err);
    return fallback;
  }
}

function writeJSON(file, data) {
  try {
    // Make a lightweight timestamped backup before overwriting
    const bakDir = join(DATA_DIR, '_backup');
    try { mkdirSync(bakDir, { recursive: true }); } catch {}
    if (existsSync(file)) {
      const ts = new Date().toISOString().replace(/[:.]/g,'-');
      const bakName = file.split('/').pop().replace(/\.json$/, '') + `.${ts}.bak.json`;
      try {
        const cur = readFileSync(file);
        writeFileSync(join(bakDir, bakName), cur);
      } catch {}
    }
  } catch {}
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

function readContacts() { return readJSON(contactsFile, []); }
function writeContacts(list) { writeJSON(contactsFile, list); }
function upsertContact(next) {
  const list = readContacts();
  const idx = list.findIndex(c => String(c.id) === String(next.id));
  const now = new Date().toISOString();
  if (idx === -1) {
    list.push({ ...next, createdAt: now, updatedAt: now });
  } else {
    list[idx] = { ...list[idx], ...next, updatedAt: now };
  }
  writeContacts(list);
  return next;
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

function isMasterWorkingOnDate(master, dateStr) {
  if (!master || !master.schedule) return true;
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return true;
  const dow = d.getDay();
  const s = master.schedule;
  if (s.type === 'weekly') {
    const days = Array.isArray(s.weekly?.days) ? s.weekly.days : [];
    return days.includes(dow);
  }
  if (s.type === 'shift') {
    const sh = s.shift || {};
    const anchor = new Date(sh.anchorDate || new Date().toISOString().slice(0,10));
    const a0 = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate());
    const d0 = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    const diffDays = Math.floor((d0 - a0) / 86400000);
    const cycle = Number(sh.workDays||2) + Number(sh.restDays||2);
    if (!Number.isFinite(cycle) || cycle <= 0) return true;
    const pos = ((diffDays % cycle) + cycle) % cycle;
    return pos < Number(sh.workDays||2);
  }
  return true;
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

  if (!masterId) {
  return 'Выберите мастера';
}

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
        { label: 'bookings.json', path: bookingsFile, get: () => readJSON(bookingsFile, []) },
        { label: 'contacts.json', path: contactsFile, get: () => readJSON(contactsFile, []) }
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
<p>BASE_URL: <code>${PUBLIC_BASE_URL}</code> · Telegram bot: <b>${TELEGRAM_BOT_TOKEN ? 'configured' : 'not set'}</b>${TELEGRAM_BOT_USERNAME ? ` · @${TELEGRAM_BOT_USERNAME}` : ''}</p>
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
<li><a href="/manager">/manager</a></li>
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
      // Если мастер указан и в этот день не работает — вернуть пустые слоты
const masters = readJSON(mastersFile, []);
const master = masterId ? masters.find(m => String(m.id) === String(masterId)) : null;
if (masterId && master && !isMasterWorkingOnDate(master, date)) {
  sendJSON(res, 200, { slots: [], meta: { slotStep: SLOT_STEP_MIN, serviceId: service?.id ?? null, serviceDuration: Math.max(SLOT_STEP_MIN, Math.ceil((duration ?? SLOT_STEP_MIN)/SLOT_STEP_MIN)*SLOT_STEP_MIN), businessHours: { open: BUSINESS_OPEN_TIME, close: BUSINESS_CLOSE_TIME } } });
  return;
}   
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
      const from = (query.from||'').trim();
      const to = (query.to||'').trim();
      const q = String(query.q||'').trim().toLowerCase();

      let out = bookings.slice();
      if (date) out = out.filter(b => b.date === date);
      if (from) out = out.filter(b => b.date >= from);
      if (to) out = out.filter(b => b.date <= to);
      if (masterId) out = out.filter(b => String(b.masterId ?? '') === String(masterId));
      if (serviceId) out = out.filter(b => String(b.serviceId) === String(serviceId));
      if (status) out = out.filter(b => b.status === status);
      if (q) out = out.filter(b => (b.clientName||'').toLowerCase().includes(q) || (b.clientPhone||'').toLowerCase().includes(q) || (b.serviceName||'').toLowerCase().includes(q));

      out.sort((a,b)=> (a.date.localeCompare(b.date)) || ((a.startTime||'').localeCompare(b.startTime||'')) );
      sendJSON(res, 200, out);
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

      // Link booking to Telegram user (if opened as WebApp) and notify client
      try {
        if (ctx.telegramId) {
          // 1) Upsert contact using provided name/phone
          const nameParts = String(payload.clientName||'').trim().split(/\s+/);
          upsertContact({
            id: ctx.telegramId,
            first_name: nameParts[0] || undefined,
            last_name: nameParts.length > 1 ? nameParts.slice(1).join(' ') : undefined,
            phone: String(payload.clientPhone||'').trim() || undefined
          });

          // 2) Send Telegram notifications
          if (TG_API) {
            const mastersList = readJSON(mastersFile, []);
            const masterName = newBooking.masterId ? (mastersList.find(m => String(m.id) === String(newBooking.masterId))?.name || 'Мастер') : 'Мастер';

            const ack = '✅ Ваша запись была сформирована, ожидайте подтверждения.';
            const details = [
              '🧾 <b>Детали записи</b>',
              `Услуга: <b>${newBooking.serviceName}</b>`,
              `Мастер: <b>${masterName}</b>`,
              `Дата: <b>${newBooking.date}</b>`,
              `Время: <b>${newBooking.startTime}</b>`,
              newBooking.serviceDuration ? `Длительность: <b>${newBooking.serviceDuration} мин</b>` : null,
              Number.isFinite(newBooking.servicePrice) ? `Стоимость: <b>${newBooking.servicePrice}₽</b>` : null
            ].filter(Boolean).join('\n');

            await tgSendMessage(ctx.telegramId, ack);
            await tgSendMessage(ctx.telegramId, details, { parse_mode: 'HTML' });
          }
        }
      } catch (e) {
        console.warn('Notify client failed:', e?.message||e);
      }

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

    // Manager UI
    if (pathname === '/manager' || pathname === '/manager/') {
      const tpl = join(__dirname, 'templates', 'managel.html');
      try {
        const html = readFileSync(tpl, 'utf-8');
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(html);
      } catch {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end('<!doctype html><meta charset="utf-8"><title>Manager</title><p>Файл templates/managel.html не найден.</p>');
      }
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
        const bootstrap = `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Авторизация…</title><style>html,body{height:100%}body{margin:0;display:grid;place-items:center;background:#f6f7fb;font-family:system-ui,-apple-system,Segoe UI,Inter,sans-serif;color:#111827}section{background:#fff;border:1px solid rgba(209,213,219,.5);border-radius:14px;padding:22px;max-width:720px;text-align:center;display:grid;gap:10px}</style></head><body><section><h1>Авторизация через Telegram…</h1><p class="muted">Если вы открыли эту страницу <b>внутри Telegram</b>, мы попробуем авторизовать вас автоматически.</p><p class="muted">Если страница не обновится в течение 3 секунд, откройте админку из бота командой <b>/admin</b>.</p></section><script>
(function(){
  function done(ok){ if(ok){ location.replace('/admin'); } else { document.body.innerHTML = '<section><h1>403</h1><p>Доступ ограничен. Откройте админку из Telegram: /admin</p></section>'; } }
  try{
    var tg = window.Telegram && window.Telegram.WebApp;
    if(tg && tg.initData){
      fetch('/auth/telegram',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({initData:tg.initData})})
        .then(function(r){ return r.ok; })
        .then(done)
        .catch(function(){ done(false); });
      setTimeout(function(){ /* fallback reload */ location.replace('/admin'); }, 3000);
    } else {
      done(false);
    }
  }catch(e){ done(false); }
})();
</script></body></html>`;
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(bootstrap);
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
         if (update.message && update.message.contact) {
           const c = update.message.contact;
           const ownerId = c.user_id || userId;
           const fromUser = from || {};
           upsertContact({
             id: ownerId,
             phone: c.phone_number,
             username: (fromUser.username||'').replace(/^@/, '') || undefined,
             first_name: fromUser.first_name || undefined,
             last_name: fromUser.last_name || undefined
           });
           await tgSendMessage(chatId, '✅ Контакт получен! Теперь можно перейти к записи.\nОткройте форму записи внутри Telegram:', {
             reply_markup: { inline_keyboard: [[{ text: '🧾 Открыть форму записи', web_app: { url: `${PUBLIC_BASE_URL}/client` } }]] }
           });
           // ✅ Important: stop further processing so we don't send fallback messages
           sendJSON(res, 200, { ok: true });
           return;
         } else if (/^\/start\b/.test(text)) {
  await tgSendMessage(chatId, 'Добро пожаловать! Нажмите кнопку «Записаться» для продолжения.', {
    reply_markup: {
      inline_keyboard: [ [ { text: '🧾 Записаться', web_app: { url: `${PUBLIC_BASE_URL}/client` } } ] ]
    }
  });
         } else if (/^\/client\b/.test(text)) {
           const url = `${PUBLIC_BASE_URL}/client`;
           await tgSendMessage(chatId, `🧾 <b>Клиентская форма</b>\n${url}`);
         } else if (/^\/admin\b/.test(text)) {
           const url = `${PUBLIC_BASE_URL}/admin`;
           // Send both text and a Web App button to open inside Telegram
           await tgSendMessage(chatId, `🛠 <b>Админ-панель</b>\nОткройте внутри Telegram для авто‑входа.\n${url}`, {
             reply_markup: {
               inline_keyboard: [ [ { text: 'Открыть админку', web_app: { url } } ] ]
             }
           });
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
      sendJSON(res, 200, { baseUrl: PUBLIC_BASE_URL, botConfigured: Boolean(TELEGRAM_BOT_TOKEN), botUsername: TELEGRAM_BOT_USERNAME });
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
        const { readdirSync, statSync, readFileSync: rf } = await import('fs');
        const { join, dirname, basename } = await import('path');

        // Detect the real data directory from any known file path we already use
        const detectedDataDir = dirname(groupsFile); // same dir as groups.json, matches /health
        const dataDir = detectedDataDir;
        const zip = new AdmZip();

        // Add every regular file from dataDir (no filtering),
        // so the archive mirrors the real /app/data contents
        let added = 0;
        try {
          const entries = readdirSync(dataDir, { withFileTypes: true });
          for (const e of entries) {
            if (!e.isFile()) continue;
            const full = join(dataDir, e.name);
            try {
              const st = statSync(full);
              if (!st.isFile()) continue;
              const content = st.size > 0 ? rf(full) : Buffer.from('');
              zip.addFile(basename(full), content);
              added++;
            } catch {}
          }
        } catch {}

        // always include manifest
        zip.addFile('manifest.json', Buffer.from(JSON.stringify({
          createdAt: new Date().toISOString(),
          version: 2,
          filesIncluded: added
        }, null, 2)));

        const name = makeBackupName();
        const buf = zip.toBuffer();
        res.writeHead(200, {
          'Content-Type': 'application/zip',
          'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(name)}`
        });
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
        const contacts = readJsonEntry('contacts.json');
        if (groups) writeJSON(groupsFile, groups);
        if (services) writeJSON(servicesFile, services);
        if (admins) writeJSON(adminsFile, admins);
        if (masters) writeJSON(mastersFile, masters);
        if (bookings) writeJSON(bookingsFile, bookings);
        if (contacts) writeJSON(contactsFile, contacts);
        const imported = {
          groups: Array.isArray(groups) ? groups.length : 0,
          services: Array.isArray(services) ? services.length : 0,
          admins: Array.isArray(admins) ? admins.length : 0,
          masters: Array.isArray(masters) ? masters.length : 0,
          bookings: Array.isArray(bookings) ? bookings.length : 0,
          contacts: Array.isArray(contacts) ? contacts.length : 0
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
server.listen(PORT, async () => {
  console.log(`✅ Сервер запущен на порту ${PORT}`);
  try {
    if (TG_API) {
      const chatId = process.env.DEPLOY_NOTIFY_CHAT_ID || '486778995'; // fallback to owner ID
      const text = `🚀 <b>Успешный деплой</b>\n\n` +
        `Приложение успешно запущено и доступно.\n\n` +
        `<b>Health:</b> ${PUBLIC_BASE_URL}/health\n` +
        `<b>Client:</b> ${PUBLIC_BASE_URL}/client\n` +
        `<b>Admin:</b> ${PUBLIC_BASE_URL}/admin\n` +
        `<b>Manager:</b> ${PUBLIC_BASE_URL}/manager\n` +
        `<b>Backup Export:</b> ${PUBLIC_BASE_URL}/api/backup/export`;
      await fetch(`${TG_API}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: chatId, text, parse_mode: 'HTML', disable_web_page_preview: true })
      });
      console.log('📨 Отправлено уведомление о деплое в Telegram');
    } else {
      console.log('⚠️ TG_API не настроен, уведомление о деплое пропущено');
    }
  } catch (err) {
    console.warn('⚠️ Не удалось отправить уведомление о деплое:', err.message);
  }
});
EOF


# --- managel.html ---
mkdir -p templates
cat <<'EOF' > templates/managel.html
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Записи — Менеджер</title>
  <style>
    :root{
      --bg:#f7f8fb;--card:#ffffff;--muted:#6b7280;--text:#0f172a;
      --line:#e5e7eb;--primary:#2563eb;--primary-weak:#eff6ff;
      --accent:#111827;--tab:#111827;--tab-muted:#9ca3af;
    }
    *{box-sizing:border-box}
    html,body{height:100%}
    body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Inter,sans-serif;background:var(--bg);color:var(--text)}
    .wrap{display:grid;grid-template-rows:auto auto auto 1fr auto;min-height:100dvh}
    /* Top view switcher */
    .views{display:flex;gap:8px;align-items:center;padding:10px 12px;position:sticky;top:0;background:var(--bg);z-index:10}
    .chip{padding:8px 12px;border:1px solid var(--line);border-radius:12px;cursor:pointer;color:var(--tab-muted);background:#fff}
    .chip.active{border-color:var(--primary);color:#fff;background:var(--primary)}
    /* Day scroller */
    .days{display:flex;gap:8px;overflow-x:auto;padding:8px 12px;border-top:1px solid var(--line);border-bottom:1px solid var(--line);background:#fff}
    .day{flex:0 0 auto;min-width:64px;padding:8px;border:1px solid var(--line);border-radius:10px;text-align:center;cursor:pointer;color:#0f172a;background:var(--primary-weak)}
    .day .dow{font-size:12px;color:var(--muted)}
    .day.active{background:var(--primary);border-color:var(--primary);color:#fff}
    .sel-date{padding:10px 16px;font-weight:700}
    /* Timeline */
    .timeline{position:relative;background:var(--card);border:1px solid var(--line);border-radius:14px;margin:0 12px 12px;height:calc(100dvh - 320px);min-height:420px;overflow:auto}
    .hour{position:relative;height:64px;border-top:1px solid var(--line);padding-left:56px;display:flex;align-items:flex-start}
    .hour:first-child{border-top:none}
    .hour .label{position:absolute;left:8px;top:6px;font-size:12px;color:var(--muted)}
    .events{position:absolute;inset:0;padding-left:56px}
    .booking{position:absolute;left:64px;right:12px;border:1px solid rgba(37,99,235,.25);background:#e8f0fe;border-left:4px solid var(--primary);border-radius:10px;padding:8px 10px;font-size:14px;line-height:1.2;overflow:hidden}
    .booking .title{font-weight:700}
    /* FAB */
    .fab{position:fixed;right:18px;bottom:calc(88px + env(safe-area-inset-bottom,0px));width:56px;height:56px;border-radius:50%;display:grid;place-items:center;background:var(--primary);color:#fff;border:none;font-size:28px;box-shadow:0 20px 40px -10px rgba(37,99,235,.4);cursor:pointer}
    /* Bottom nav */
    .nav{position:sticky;bottom:0;background:#fff;border-top:1px solid var(--line);display:flex;justify-content:space-around;padding:8px 6px}
    .nav a{display:grid;gap:4px;justify-items:center;text-decoration:none;color:var(--muted);font-size:12px}
    .nav a.active{color:var(--primary)}
    .nav .dot{width:24px;height:24px;border-radius:8px;border:1px solid var(--line);display:grid;place-items:center}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="views">
      <button class="chip active" data-view="day">День</button>
      <button class="chip" data-view="week">Неделя</button>
      <button class="chip" data-view="month">Месяц</button>
      <button class="chip" data-view="list">Список</button>
    </div>
    <div class="days" id="days"></div>
    <div class="sel-date" id="selDate"></div>
    <div class="timeline" id="timeline">
      <div class="events" id="events"></div>
    </div>
    <nav class="nav">
      <a href="#" class="active"><div class="dot">📄</div><span>Записи</span></a>
      <a href="/manager?schedule"><div class="dot">📆</div><span>График</span></a>
      <a href="/admin"><div class="dot">🛠</div><span>Управление</span></a>
      <a href="/health"><div class="dot">⚙️</div><span>Настройки</span></a>
    </nav>
  </div>
  <button class="fab" id="fab" title="Добавить запись">+</button>

  <script>
    const pad = n => String(n).padStart(2,'0');
    const toISO = d => d.toISOString().slice(0,10);
    const fromISO = s => { const [y,m,d]=s.split('-').map(Number); return new Date(y,m-1,d); };
    const addDays = (d,n)=>{ const x=new Date(d); x.setDate(x.getDate()+n); return x; };
    const fmtRu = d => d.toLocaleDateString('ru-RU',{weekday:'long',day:'numeric',month:'long'});
    const fmtDow = d => d.toLocaleDateString('ru-RU',{weekday:'short'});

    let state = {
      date: toISO(new Date()),
      daysRange: { start: toISO(addDays(new Date(), -31)), end: toISO(addDays(new Date(), 31)) }
    };

    const daysDiff = (a,b)=> Math.round((fromISO(b)-fromISO(a))/86400000);
    const clampToRange = (iso)=>{
      const s=fromISO(state.daysRange.start), e=fromISO(state.daysRange.end);
      const d=fromISO(iso);
      if(d<s) return toISO(s);
      if(d>e) return toISO(e);
      return iso;
    };

    function buildDaysStrip(center=false){
      const daysEl=document.getElementById('days');
      daysEl.innerHTML='';
      const start=fromISO(state.daysRange.start);
      const total=daysDiff(state.daysRange.start,state.daysRange.end)+1;
      for(let i=0;i<total;i++){
        const d=addDays(start,i);
        const iso=toISO(d);
        const el=document.createElement('div');
        el.className='day'+(iso===state.date?' active':'');
        el.dataset.iso=iso;
        el.innerHTML='<div class="dow">'+fmtDow(d)+'</div><div><b>'+d.getDate()+'</b> '+d.toLocaleDateString('ru-RU',{month:'short'})+'</div>';
        el.onclick=()=>selectDate(iso);
        daysEl.appendChild(el);
      }
      if(center){
        const active=[...daysEl.children].find(c=>c.dataset.iso===state.date);
        if(active) daysEl.scrollLeft=active.offsetLeft-(daysEl.clientWidth/2-active.clientWidth/2);
      }
      updateSelectedDateLabel();
    }

    function updateSelectedDateLabel(){
      document.getElementById('selDate').textContent='Выбрано: '+fmtRu(fromISO(state.date));
    }

    async function selectDate(iso){
      state.date=clampToRange(iso);
      [...document.querySelectorAll('.day')].forEach(d=>d.classList.toggle('active',d.dataset.iso===state.date));
      updateSelectedDateLabel();
    }

    function onDaysScroll(){ /* Диапазон фиксирован ±1 месяц */ }

    document.addEventListener('DOMContentLoaded',()=>{
      buildDaysStrip(true);
      document.getElementById('fab').onclick=()=>location.href='/client';
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
  if (tg) { tg.ready && tg.ready(); tg.expand && tg.expand(); }
  if (tg && tg.initData) {
    // If no tg_id cookie yet — authenticate and reload to apply cookies to same-origin requests
    var hasCookie = document.cookie.split(';').some(function(p){ return p.trim().startsWith('tg_id='); });
    if (!hasCookie) {
      fetch('/auth/telegram', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ initData: tg.initData }) })
        .then(function(r){ if(r.ok){ location.reload(); } })
        .catch(function(){});
    }
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
    // ===== CONTACTS API =====
    if (pathname === '/api/contacts/me' && req.method === 'GET') {
      if (!ctx.telegramId) { sendJSON(res, 200, { contact: null }); return; }
      const list = readContacts();
      const c = list.find(x => String(x.id) === String(ctx.telegramId)) || null;
      sendJSON(res, 200, { contact: c });
      return;
    }

    if (pathname === '/api/contacts/bootstrap' && req.method === 'POST') {
      // Upsert from WebApp: we trust cookie set via /auth/telegram; optionally merge name/username in body
      if (!ctx.telegramId) { sendJSON(res, 400, { error: 'not in Telegram WebApp (no tg_id)' }); return; }
      let body = {};
      try { body = JSON.parse(await readBody(req) || '{}'); } catch {}
      const next = {
        id: ctx.telegramId,
        username: (body.username ?? '').replace(/^@/, '') || undefined,
        first_name: body.first_name ?? undefined,
        last_name: body.last_name ?? undefined,
        phone: body.phone ?? undefined
      };
      upsertContact(next);
      sendJSON(res, 200, { ok: true });
      return;
    }
#
# --- manager (templates/managel.html) ---
cat <<'EOF' > templates/managel.html
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Менеджер — Записи</title>
  <style>
    *,*::before,*::after{box-sizing:border-box}
    html,body{height:100%}
    body{margin:0;font-family:Inter,system-ui,-apple-system,Segoe UI,Roboto,Arial;background:#f6f7fb;color:#111827}
    header{position:sticky;top:0;background:#fff;border-bottom:1px solid #e5e7eb;z-index:10}
    .top{display:flex;align-items:center;justify-content:space-between;padding:12px}
    .chips{display:flex;gap:8px}
    .chip{padding:8px 12px;border:1px solid #d1d5db;border-radius:12px;background:#fff;cursor:pointer;font-weight:700}
    .chip.active{background:#007aff;color:#fff;border-color:#007aff}
    main{padding:12px;display:grid;gap:12px}
    .grid{display:grid;grid-template-columns:64px 1fr;gap:10px;background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:10px;box-shadow:0 24px 40px -32px rgba(15,23,42,.25)}
    .hours{display:grid}
    .h{height:56px;font-size:12px;color:#6b7280;display:flex;align-items:flex-start;justify-content:flex-end;padding:8px}
    .lane{position:relative;border-left:1px dashed #e5e7eb;min-height:56px}
    .event{position:absolute;left:10px;right:10px;border-radius:12px;padding:8px 10px;background:#eef6ff;border:1px solid #c7ddff}

  .fab{
    position:fixed;
    right:18px;
    bottom:calc(88px + env(safe-area-inset-bottom,0px)); /* было 24px */
    width:56px;height:56px;border-radius:50%;
    display:grid;place-items:center;background:var(--primary);color:#fff;
    border:none;font-size:28px;box-shadow:0 20px 40px -10px rgba(37,99,235,.4);cursor:pointer
  }

    .modal{position:fixed;inset:0;background:rgba(15,23,42,.4);display:none;align-items:center;justify-content:center;z-index:40;padding:12px}
    .modal.show{display:flex}
    .card{width:100%;max-width:520px;background:#fff;border:1px solid #e5e7eb;border-radius:14px;box-shadow:0 30px 60px -40px rgba(15,23,42,.4);padding:14px}
    label{display:grid;gap:6px;font-size:14px;color:#4b5563;margin:6px 0}
    input,select,textarea{width:100%;padding:12px 14px;border:1px solid rgba(148,163,184,.45);border-radius:12px;font:inherit;background:#fff}
    .row{display:flex;gap:10px;flex-wrap:wrap}
    .row>.col{flex:1 1 180px}
    .actions{display:flex;gap:10px;justify-content:flex-end;margin-top:8px}
    .btn{padding:10px 14px;border-radius:12px;border:1px solid rgba(148,163,184,.45);background:#fff;font-weight:700;cursor:pointer}
    .primary{border:none;background:#007aff;color:#fff}
  </style>
</head>
<body>
  <header>
    <div class="top">
      <div style="font-weight:800">Менеджер</div>
      <div class="chips">
        <button class="chip active" data-view="day">День</button>
        <button class="chip" data-view="week">Неделя</button>
        <button class="chip" data-view="month">Месяц</button>
        <button class="chip" data-view="list">Список</button>
      </div>
    </div>
  </header>
  <main>
    <div id="dateLabel" style="font-weight:800"></div>
    <div id="viewDay" class="grid">
      <div id="hours" class="hours"></div>
      <div id="lane" class="lane"></div>
    </div>
    <div id="viewWeek" class="grid" style="display:none">
      <div id="hoursW" class="hours"></div>
      <div id="laneW" class="lane"></div>
    </div>
    <div id="viewMonth" style="display:none">(Заглушка «Месяц»)</div>
    <div id="viewList" style="display:none">(Заглушка «Список»)</div>
  </main>
  <button class="fab" id="fab">+</button>

  <div class="modal" id="modal">
    <div class="card">
      <h3 style="margin:0 0 8px">Новая запись</h3>
      <div class="row">
        <div class="col"><label>Имя<input id="bName" type="text" placeholder="Иван Иванов"></label></div>
        <div class="col"><label>Телефон<input id="bPhone" type="tel" placeholder="+375..."></label></div>
      </div>
      <div class="row">
        <div class="col"><label>Услуга<select id="bService"></select></label></div>
        <div class="col"><label>Мастер<select id="bMaster"><option value=\"\">Все мастера</option></select></label></div>
      </div>
      <div class="row">
        <div class="col"><label>Дата<input id="bDate" type="date"></label></div>
        <div class="col"><label>Время<select id="bTime"></select></label></div>
      </div>
      <label>Комментарий<textarea id="bNotes"></textarea></label>
      <div class="actions">
        <button class="btn" id="bCancel" type="button">Отмена</button>
        <button class="btn primary" id="bSave" type="button">Создать</button>
      </div>
    </div>
  </div>

<script>
(function(){
  const chips=document.querySelectorAll('.chip');
  const views={day:document.getElementById('viewDay'), week:document.getElementById('viewWeek'), month:document.getElementById('viewMonth'), list:document.getElementById('viewList')};
  const dateLabel=document.getElementById('dateLabel');
  const hours=document.getElementById('hours');
  const lane=document.getElementById('lane');
  let cursor=new Date();
  const hoursList=[...Array(12)].map((_,i)=>i+9);
  function ymd(d){const y=d.getFullYear(),m=String(d.getMonth()+1).padStart(2,'0'),da=String(d.getDate()).padStart(2,'0');return `${y}-${m}-${da}`}
  function toMin(t){const[a,b]=String(t||'00:00').split(':').map(Number);return a*60+b}
  function renderHours(){hours.innerHTML='';hoursList.forEach(h=>{const el=document.createElement('div');el.className='h';el.textContent=String(h).padStart(2,'0')+':00';hours.appendChild(el);});}
  async function loadDay(){
    renderHours(); lane.innerHTML='';
    const d=ymd(cursor); dateLabel.textContent='Выбрано: '+cursor.toLocaleDateString('ru-RU',{weekday:'long',day:'numeric',month:'long'});
    const r=await fetch(`/api/bookings?from=${d}&to=${d}`);
    const list=r.ok?await r.json():[];
    const perMin=56/60;
    list.forEach(b=>{const top=Math.max(0,(toMin(b.startTime)-(9*60))*perMin);const dur=Number(b.duration||30);const h=Math.max(36,Math.round(dur*perMin));const e=document.createElement('div');e.className='event';e.style.top=top+'px';e.style.height=h+'px';e.innerHTML=`<b>${b.startTime}</b> — ${b.clientName||''}<br><small>${b.serviceName||''}</small>`;lane.appendChild(e);});
  }
  function setView(v){Object.keys(views).forEach(k=>views[k].style.display=k===v?'grid':'none');chips.forEach(c=>c.classList.toggle('active',c.dataset.view===v));if(v==='day') loadDay();}
  chips.forEach(c=>c.addEventListener('click',()=>setView(c.dataset.view)));
  setView('day');

  // Modal
  const modal=document.getElementById('modal');
  const fab=document.getElementById('fab');
  const bName=document.getElementById('bName');
  const bPhone=document.getElementById('bPhone');
  const bService=document.getElementById('bService');
  const bMaster=document.getElementById('bMaster');
  const bDate=document.getElementById('bDate');
  const bTime=document.getElementById('bTime');
  const bNotes=document.getElementById('bNotes');
  function openModal(){modal.classList.add('show');bDate.value=ymd(cursor);loadRefs().then(loadSlots);} 
  function closeModal(){modal.classList.remove('show');}
  document.getElementById('bCancel').addEventListener('click',closeModal);
  fab.addEventListener('click',openModal);

  async function loadRefs(){
    if(!bService.options.length){
      const rs=await fetch('/api/services'); const sj=rs.ok?await rs.json():[]; bService.innerHTML='<option value=\"\" disabled selected>Выберите услугу…</option>'+sj.map(s=>`<option value=\"${s.id}\">${s.name} • ${s.duration} мин</option>`).join('');
    }
    if(bMaster.options.length<=1){
      const rm=await fetch('/api/masters'); const mj=rm.ok?await rm.json():[]; bMaster.innerHTML='<option value=\"\">Все мастера</option>'+mj.map(m=>`<option value=\"${m.id}\">${m.name}</option>`).join('');
    }
  }
  async function loadSlots(){
    const date=bDate.value; const serviceId=bService.value; const masterId=bMaster.value||''; if(!date||!serviceId){bTime.innerHTML='<option disabled selected>Выберите услугу и дату</option>';return}
    const url=new URL('/api/availability',location.origin); url.searchParams.set('date',date); url.searchParams.set('serviceId',serviceId); if(masterId) url.searchParams.set('masterId',masterId);
    const r=await fetch(url); const j=r.ok?await r.json():{slots:[]}; const slots=(j.slots||[]).filter(s=>s.available);
    bTime.innerHTML=slots.length?('<option disabled selected>Выберите время…</option>'+slots.map(s=>`<option value=\"${s.startTime}\">${s.startTime}</option>`).join('')):'<option disabled selected>Нет доступных слотов</option>';
  }
  bService.addEventListener('change',loadSlots); bMaster.addEventListener('change',loadSlots); bDate.addEventListener('change',loadSlots);

  document.getElementById('bSave').addEventListener('click', async ()=>{
    const payload={clientName:bName.value.trim(),clientPhone:bPhone.value.trim(),serviceId:Number(bService.value),masterId:bMaster.value||null,date:bDate.value,startTime:bTime.value,notes:bNotes.value.trim()};
    if(!payload.clientName||!payload.clientPhone||!payload.serviceId||!payload.date||!payload.startTime){alert('Заполните обязательные поля');return}
    const res=await fetch('/api/bookings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
    if(!res.ok){const err=await res.json().catch(()=>({}));alert(err.error||'Не удалось создать запись');return}
    closeModal(); loadDay();
  });
})();
</script>
</body>
</html>
EOF