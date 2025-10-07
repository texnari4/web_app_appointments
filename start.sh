#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> 🚀 Развёртывание мини-приложения (сервер + админка v13)..."

# --- Подготовка директорий ---
# mkdir -p app/data - создаётся автоматически при первом запуске, включить при первом деплое
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
        const names = require('fs').readdirSync(bakDir)
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

#
# --- client.html ---
cat <<'EOF' >  public/client.html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Запись в салон — Beauty Appointments</title>
  <style>
    /* Reset & base */
    *, *::before, *::after { box-sizing: border-box; }
    html, body { height: 100%; }
    body { margin:0; -webkit-text-size-adjust:100%; font-family: 'SF Pro Display','Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif; background:linear-gradient(180deg,#f6f7fb 0%,#f0f3f8 45%,#eef1f7 100%); color:#111827; overflow-x:hidden; }

    /* Layout */
    .container { max-width: 720px; margin: 0 auto; padding: 24px 12px calc(28px + env(safe-area-inset-bottom,0)); }
    header { text-align: center; display: grid; gap: 8px; margin-bottom: 12px; }
    header h1 { margin: 0; font-weight: 800; letter-spacing: -0.02em; font-size: clamp(24px, 5vw, 34px); }
    header p { margin: 0 auto; max-width: 520px; color:#4b5563; font-size: 15px; line-height: 1.5; }

    .card { position: relative; background: #fff; border: 1px solid rgba(209,213,219,.5); border-radius: 16px; box-shadow: 0 30px 60px -40px rgba(15,23,42,.35); padding: 16px; overflow:hidden; }

    /* Steps (simple show/hide, no wide carousels => нет горизонтального скролла) */
    .step { display: none; }
    .step.active { display: block; }

    .step h2 { margin: 0 0 12px; font-size: 20px; font-weight: 700; }
    .step { padding: 2px 0; }

    .form-grid { display: grid; gap: 12px; }
    label { display: grid; gap: 6px; font-size: 14px; color:#4b5563; }
    input, select, textarea {
      width:100%; padding: 12px 14px; border: 1px solid rgba(148,163,184,.45); border-radius: 12px;
      font: inherit; font-size:16px; line-height:1.2; background:#fff;
    }
    input:focus, select:focus, textarea:focus { outline: none; border-color: rgba(99,102,241,.9); box-shadow: 0 0 0 3px rgba(99,102,241,.18); }
    textarea { min-height: 90px; resize: vertical; }

    .actions { display: grid; gap: 10px; margin-top: 12px; }
    .btn { display: block; width: 100%; padding: 12px 18px; border-radius: 12px; border: 1px solid rgba(148,163,184,.45); background: #fff; color:#111827; font-weight: 700; cursor: pointer; font-size:16px; }
    .btn.primary { border: none; background: linear-gradient(135deg,#5ec5ff,#007aff); color:#fff; box-shadow: 0 24px 40px -28px rgba(0,122,255,.55); }
    .btn[disabled] { opacity:.6; cursor:not-allowed; }

    .muted { color:#6b7280; font-size: 13px; }

    .slot-grid { display:grid; grid-template-columns: repeat(auto-fill,minmax(120px,1fr)); gap:12px; margin-top:6px; }
    .slot-button { padding:12px; border-radius:14px; border:1px solid rgba(148,163,184,.4); background:rgba(255,255,255,.92); cursor:pointer; font-size:15px; font-weight:500; display:grid; gap:4px; justify-items:center; }
    .slot-button.selected { border-color:transparent; background:linear-gradient(130deg,#4ade80,#34c759); color:#fff; box-shadow:0 24px 32px -24px rgba(52,199,89,.55); }
    .slot-button[disabled] { cursor:not-allowed; opacity:.45; }

    .summary { border:1px solid rgba(209,213,219,.5); background:rgba(249,250,251,.9); border-radius: 14px; padding:10px 12px; display:grid; gap:6px; }

    /* Calendar */
.cal { display:grid; gap:10px; }
.cal-head { display:flex; align-items:center; justify-content:space-between; }
.cal-head b { font-weight:800; letter-spacing:-0.02em; }
.cal-grid { display:grid; grid-template-columns: repeat(7, 1fr); gap:6px; }
.cal-dow { text-align:center; font-size:12px; color:#6b7280; padding:6px 0; }
.cal-day { text-align:center; padding:10px 0; border:1px solid rgba(148,163,184,.35); border-radius:10px; background:#fff; cursor:pointer; user-select:none; }
.cal-day.mute { color:#9ca3af; background:#f3f4f6; border-color:rgba(148,163,184,.25); cursor:not-allowed; }
.cal-day.today { outline:2px solid rgba(99,102,241,.35); }
.cal-day.sel { background:linear-gradient(135deg,#5ec5ff,#007aff); color:#fff; border-color:transparent; }
.cal-nav { display:inline-flex; gap:6px; }
.cal-btn { border:1px solid rgba(148,163,184,.45); background:#fff; padding:6px 10px; border-radius:10px; cursor:pointer; }

    .banner { position:fixed; left:0; right:0; bottom: calc(18px + env(safe-area-inset-bottom,0)); margin: 0 auto; max-width: 720px; padding: 12px 16px; border-radius: 12px; background: linear-gradient(135deg, rgba(94,197,255,.95), rgba(0,122,255,.95)); color:#fff; font-weight:700; box-shadow:0 32px 48px -32px rgba(0,122,255,.55); text-align:center; opacity:0; pointer-events:none; transform: translateY(6px); transition: opacity .2s ease, transform .2s ease; }
    .banner.show { opacity:1; transform: translateY(0); }
    .banner.error { background: linear-gradient(135deg, rgba(255,95,95,.95), rgba(244,63,94,.95)); box-shadow:0 32px 48px -32px rgba(244,63,94,.6); }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>Запишитесь в любимый салон</h1>
      <p>Три шага: контакты → услуга → дата и мастер. Мы напомним вам о визите в Telegram.</p>
    </header>

    <div class="card">
      <!-- Шаг 1 -->
      <section class="step active" id="step1">
        <h2>Шаг 1 из 3 — Контакты</h2>
        <div class="form-grid">
          <label>Как к вам обращаться
            <input type="text" id="clientName" placeholder="Имя и фамилия" required />
          </label>
          <label>Телефон
            <input type="tel" id="clientPhone" placeholder="+375 (29) 123-45-67" required />
          </label>
        </div>
        <div class="actions">
          <button id="next1" class="btn primary" type="button">Продолжить</button>
        </div>
      </section>

      <!-- Шаг 2 -->
      <section class="step" id="step2">
        <h2>Шаг 2 из 3 — Услуга</h2>
        <div class="form-grid">
          <label>Услуга
            <select id="serviceSelect" required>
              <option value="" disabled selected>Загружаю список…</option>
            </select>
          </label>
          <label>Комментарий для мастера (необязательно)
            <textarea id="clientNotes" placeholder="Например: хочу нежный пастельный оттенок"></textarea>
          </label>
          <div class="summary" id="serviceSummary" hidden></div>
        </div>
        <div class="actions">
          <button id="back2" class="btn" type="button">Назад</button>
          <button id="next2" class="btn primary" type="button">Далее</button>
        </div>
      </section>

      <!-- Шаг 3 -->
      <section class="step" id="step3">
        <h2>Шаг 3 из 3 — Дата и мастер</h2>
        <div class="form-grid">
          <label>Мастер <span style="color:#dc2626">*</span>
            <select id="bookingMaster" required></select>
          </label>
          <input type="date" id="dateInput" required style="display:none" />
<div id="calendar" class="cal" aria-label="Выбор даты визита">
  <div class="cal-head">
    <div class="cal-nav">
      <button type="button" id="calPrev" class="cal-btn" aria-label="Предыдущий месяц">‹</button>
      <button type="button" id="calNext" class="cal-btn" aria-label="Следующий месяц">›</button>
    </div>
    <b id="calTitle"></b>
    <span style="width:52px"></span>
  </div>
  <div class="cal-grid" id="calGrid"><!-- сюда рендерятся дни --></div>
</div>
<p class="muted" id="availabilityHint">Выберите услугу, мастера и дату, чтобы увидеть свободные слоты.</p>

          
           </div>
        <div id="slotsContainer" class="slot-grid"></div>
        <p class="muted" id="slotsEmpty" hidden>На выбранный день пока нет свободных окон. Попробуйте другую дату.</p>
        <div class="actions">
          <button id="back3" class="btn" type="button">Назад</button>
          <button id="submit" class="btn primary" type="button">Подтвердить запись</button>
        </div>
      </section>

      <!-- Шаг 4 -->
      <section class="step" id="step4">
        <h2>Заявка отправлена</h2>
        <div class="summary" id="finalSummary"></div>
        <div class="actions">
          <button id="closeApp" class="btn primary" type="button">Закрыть</button>
        </div>
      </section>
    </div>


    <div class="banner" id="banner" hidden></div>
  </div>

  <script>
  document.addEventListener('DOMContentLoaded', () => {
    // Telegram WebApp adjustments
    try { const tg = window.Telegram && window.Telegram.WebApp; if (tg) { tg.ready && tg.ready(); tg.expand && tg.expand(); } } catch(_){ }

    async function ensureTgAuth(){
    try{
      const tg = window.Telegram && window.Telegram.WebApp;
      if (!tg || !tg.initData || tg.initData.length < 10) return;
      await fetch('/auth/telegram', {
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ initData: tg.initData })
      });
    }catch(e){}
  }


    // Elements
    const step1 = document.getElementById('step1');
    const step2 = document.getElementById('step2');
    const step3 = document.getElementById('step3');
    const step4 = document.getElementById('step4');
    const banner = document.getElementById('banner');

    const next1 = document.getElementById('next1');
    const back2 = document.getElementById('back2');
    const next2 = document.getElementById('next2');
    const back3 = document.getElementById('back3');
    const submitBtn = document.getElementById('submit');
    // Re-bind close button for step 4 (works regardless of DOM order)
    const closeBtn = document.getElementById('closeApp');
    if (closeBtn) closeBtn.addEventListener('click', ()=>{
      try { const tg = window.Telegram && window.Telegram.WebApp; if (tg && tg.close) { tg.close(); return; } } catch(_){}
      window.location.replace('/client');
    });

    const clientNameInput = document.getElementById('clientName');
    const clientPhoneInput = document.getElementById('clientPhone');
    const clientNotesInput = document.getElementById('clientNotes');
    const serviceSelect = document.getElementById('serviceSelect');
    const serviceSummary = document.getElementById('serviceSummary');
    const bookingMasterSelect = document.getElementById('bookingMaster');
    const dateInput = document.getElementById('dateInput');
    const availabilityHint = document.getElementById('availabilityHint');
    const slotsContainer = document.getElementById('slotsContainer');
    const slotsEmpty = document.getElementById('slotsEmpty');

    bookingMasterSelect.addEventListener('change', ()=>{
  const id = bookingMasterSelect.value;
  selectedMaster = mastersCache.find(m=>String(m.id)===String(id)) || null;
  renderCalendar();
  if(dateInput.value) fetchAvailability();
});

    // Calendar state
let calMonth = new Date(); // текущий показанный месяц
calMonth.setDate(1);
let mastersCache = [];
let selectedMaster = null;

function ymd(d){ const y=d.getFullYear(); const m=String(d.getMonth()+1).padStart(2,'0'); const dd=String(d.getDate()).padStart(2,'0'); return `${y}-${m}-${dd}`; }

function isMasterWorkingOnDateLocal(master, dateStr){
  if(!master || !master.schedule) return true;
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

function renderCalendar(){
  const grid = document.getElementById('calGrid');
  const title = document.getElementById('calTitle');
  const m = calMonth.getMonth(); const y = calMonth.getFullYear();
  title.textContent = calMonth.toLocaleDateString('ru-RU', { month:'long', year:'numeric' });
  grid.innerHTML = '';
  // header dow
  const dows = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
  dows.forEach(d=>{ const el=document.createElement('div'); el.className='cal-dow'; el.textContent=d; grid.appendChild(el); });
  const firstDay = new Date(y, m, 1);
  const startIndex = (firstDay.getDay()+6)%7; // monday=0
  const daysInMonth = new Date(y, m+1, 0).getDate();
  // blanks
  for(let i=0;i<startIndex;i++){ grid.appendChild(document.createElement('div')); }
  const todayStr = ymd(new Date());
  for(let day=1; day<=daysInMonth; day++){
    const d = new Date(y, m, day);
    const ds = ymd(d);
    const btn = document.createElement('button');
    btn.type='button'; btn.className='cal-day'; btn.textContent=String(day);
    const isPast = ds < todayStr;
    const works = selectedMaster ? isMasterWorkingOnDateLocal(selectedMaster, ds) : true;
    if(isPast || !works){ btn.classList.add('mute'); btn.disabled = true; }
    if(ds === todayStr) btn.classList.add('today');
    btn.addEventListener('click', ()=>{
      document.querySelectorAll('.cal-day.sel').forEach(x=>x.classList.remove('sel'));
      btn.classList.add('sel');
      dateInput.value = ds;
      fetchAvailability();
    });
    grid.appendChild(btn);
  }
}

document.getElementById('calPrev').addEventListener('click', ()=>{ calMonth.setMonth(calMonth.getMonth()-1); renderCalendar(); });
document.getElementById('calNext').addEventListener('click', ()=>{ calMonth.setMonth(calMonth.getMonth()+1); renderCalendar(); });


    function showBanner(msg, type) {
      banner.textContent = msg;
      banner.classList.toggle('error', type === 'error');
      banner.hidden = false; requestAnimationFrame(() => banner.classList.add('show'));
      setTimeout(() => { banner.classList.remove('show'); setTimeout(() => banner.hidden = true, 180); }, 2200);
    }

    function setStep(n){
      step1.classList.toggle('active', n===1);
      step2.classList.toggle('active', n===2);
      step3.classList.toggle('active', n===3);
      step4.classList.toggle('active', n===4);
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    function isValidPhone(p){
      const v = String(p||'').trim();
      const digits = v.replace(/\D/g,'');
      if (digits.length < 10) return false;
      return /^\+?[\d\s\-()]{10,}$/.test(v);
    }

    // Prefill contact by cookie tg_id if available
    async function prefill(){
      try{
        const r = await fetch('/api/contacts/me'); if(!r.ok) return;
        const j = await r.json(); const c = j.contact;
        if(c){
          if(!clientNameInput.value && (c.first_name||c.last_name)) clientNameInput.value = [c.first_name||'', c.last_name||''].join(' ').trim();
          if(!clientPhoneInput.value && c.phone) clientPhoneInput.value = c.phone;
        }
      }catch{}
    }

    async function loadServices(){
      const r = await fetch('/api/services');
      const list = r.ok ? await r.json() : [];
      serviceSelect.innerHTML = '<option value="" disabled selected>Выберите услугу…</option>' +
        list.map(s=>`<option value="${s.id}" data-duration="${s.duration}" data-price="${s.price}">${s.name}</option>`).join('');
      return list;
    }

async function loadMasters(){
  const r = await fetch('/api/masters');
  mastersCache = r.ok ? await r.json() : [];
  bookingMasterSelect.innerHTML = '<option value="" disabled selected>Выберите мастера…</option>' +
   
   
    mastersCache.map(m=>`<option value="${m.id}">${m.name}</option>`).join('');
  return mastersCache;
}

    function clearSlots(){ slotsContainer.innerHTML = ''; slotsEmpty.hidden = true; }

    async function fetchAvailability(){
      clearSlots();
      if(!serviceSelect.value || !dateInput.value || !bookingMasterSelect.value){
        availabilityHint.textContent = 'Выберите услугу, мастера и дату.'; return;
      }
      availabilityHint.textContent = 'Ищу свободные слоты…';
      const params = new URLSearchParams({ serviceId: serviceSelect.value, date: dateInput.value, masterId: bookingMasterSelect.value });
      const r = await fetch('/api/availability?' + params.toString());
      if(!r.ok){ availabilityHint.textContent = 'Ошибка загрузки слотов'; return; }
      
      const data = await r.json(); const raw = data?.slots || [];
const slots = raw.filter(s => s.available === true);
if(!slots.length){ slotsEmpty.hidden = false; availabilityHint.textContent = 'Свободных слотов нет'; return; }
availabilityHint.textContent = 'Выберите удобное время';
slots.forEach(s=>{
  const btn = document.createElement('button');
  btn.type='button'; btn.className='slot-button'; btn.textContent = `${s.startTime}–${s.endTime}`;
  btn.addEventListener('click',()=>{
    document.querySelectorAll('.slot-button.selected').forEach(b=>b.classList.remove('selected'));
    btn.classList.add('selected'); btn.dataset.value = s.startTime;
  });
  slotsContainer.appendChild(btn);
});
    }

    // Step 1
    next1.addEventListener('click', () => {
      const name = clientNameInput.value.trim();
      const phone = clientPhoneInput.value.trim();
      if(!name){ showBanner('Укажите имя', 'error'); return; }
      if(!phone){ showBanner('Укажите номер телефона', 'error'); return; }
      if(!isValidPhone(phone)){ showBanner('Проверьте формат номера телефона', 'error'); return; }
      setStep(2);
    });

    // Step 2
    back2.addEventListener('click', () => setStep(1));
    next2.addEventListener('click', () => {
      if(!serviceSelect.value){ showBanner('Выберите услугу', 'error'); return; }
      const opt = serviceSelect.selectedOptions[0];
      const price = opt?.dataset?.price; const duration = opt?.dataset?.duration;
      serviceSummary.hidden = false; serviceSummary.innerHTML = `<b>${opt.textContent}</b><span class="muted">Длительность: ${duration} мин · Цена: ${price}₽</span>`;
      setStep(3); fetchAvailability();
    });

    // Step 3
    back3.addEventListener('click', () => setStep(2));
    bookingMasterSelect.addEventListener('change', () => { if(dateInput.value) fetchAvailability(); });
    dateInput.addEventListener('change', () => fetchAvailability());

    submitBtn.addEventListener('click', async () => {
      const name = clientNameInput.value.trim();
      const phone = clientPhoneInput.value.trim();
      if(!name || !phone || !isValidPhone(phone)){ setStep(1); showBanner('Проверьте контакты', 'error'); return; }
      const serviceId = Number(serviceSelect.value);
      const masterId = bookingMasterSelect.value; const date = dateInput.value;
      const slotBtn = document.querySelector('.slot-button.selected'); const startTime = slotBtn && slotBtn.dataset.value;
      if(!serviceId){ setStep(2); showBanner('Выберите услугу', 'error'); return; }
      if(!masterId || !date || !startTime){ setStep(3); showBanner('Выберите мастера, дату и время', 'error'); return; }
      const payload = { clientName:name, clientPhone:phone, notes: clientNotesInput.value.trim(), serviceId, masterId, date, startTime };
      const r = await fetch('/api/bookings', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload) });
      if(!r.ok){ const j = await r.json().catch(()=>({})); showBanner(j.error||'Ошибка сохранения', 'error'); return; }
      const opt = serviceSelect.selectedOptions[0];
const chosenService = opt ? opt.textContent : '';
const chosenMaster = (bookingMasterSelect.selectedOptions[0]||{}).textContent || '';
const final = document.getElementById('finalSummary');
final.innerHTML = [
  `<b>Спасибо! Заявка отправлена</b>`,
  `Имя: <b>${name}</b>`,
  `Телефон: <b>${phone}</b>`,
  `Услуга: <b>${chosenService}</b>`,
  `Мастер: <b>${chosenMaster}</b>`,
  `Дата: <b>${date}</b>`,
  `Время: <b>${startTime}</b>`
].join('<br>');
setStep(4);
      setTimeout(()=>{ try{ const tg = window.Telegram && window.Telegram.WebApp; tg && tg.close && tg.close(); }catch(_){} }, 1400);
    });

    document.getElementById('closeApp').addEventListener('click', ()=>{
  try { const tg = window.Telegram && window.Telegram.WebApp; if (tg && tg.close) { tg.close(); return; } } catch(_){}
  window.location.replace('/client');
});

    // Init
    ensureTgAuth();
    prefill();
    loadServices();
    loadMasters().then(()=>{ renderCalendar(); });

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