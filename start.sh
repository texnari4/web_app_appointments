#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

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

const MAX_LOG = 300;
const LOGS = { ops: [], err: [], req: [], backup: [] };
function pushLog(type, entry){
  try{
    const arr = LOGS[type]; if(!arr) return;
    arr.push({ ts: new Date().toISOString(), ...entry });
    if(arr.length > MAX_LOG) arr.splice(0, arr.length - MAX_LOG);
  }catch{}
}

const servicesFile = join(DATA_DIR, 'services.json');
const groupsFile = join(DATA_DIR, 'groups.json');
const bookingsFile = join(DATA_DIR, 'bookings.json');
const adminsFile = join(DATA_DIR, 'admins.json');
const mastersFile = join(DATA_DIR, 'masters.json');
const contactsFile = join(DATA_DIR, 'contacts.json');
const hostesFile = join(DATA_DIR, 'hostes.json');


const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || null;
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || 'https://beautyminiappappointments-production.up.railway.app').replace(/\/+$/,'');
const TG_API = TELEGRAM_BOT_TOKEN ? `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}` : null;
const TELEGRAM_BOT_USERNAME = process.env.TELEGRAM_BOT_USERNAME || null;
const OWNER_TG_ID = Number(process.env.OWNER_TG_ID || 0) || null;

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

// ==== Authorization helpers (Telegram ID based) ====
function getAdminAuth(req) {
  const id = Number(req.headers['x-telegram-id'] || 0);
  const admins = readJSON(adminsFile, []);
  const admin = admins.find(a => String(a.id) === String(id));
  return { authenticated: Boolean(admin), admin: admin || null };
}

function requireAdmin(req, res) {
  const auth = getAdminAuth(req);
  if (!auth.authenticated) {
    sendJSON(res, 401, { error: 'Unauthorized: provide X-Telegram-Id of an admin' });
    return null;
  }
  return auth;
}

function requireOwner(req, res) {
  const auth = getAdminAuth(req);
  if (!auth.authenticated) {
    sendJSON(res, 401, { error: 'Unauthorized' });
    return null;
  }
  if ((auth.admin?.role || 'admin') !== 'owner') {
    sendJSON(res, 403, { error: 'Only the owner can perform this action' });
    return null;
  }
  return auth;
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
        pushLog('backup', { file: file.split('/').pop(), name: bakName, size: cur.length });
      } catch {}
    }
  } catch {}
  writeFileSync(file, JSON.stringify(data, null, 2));
  const isArr = Array.isArray(data);
  pushLog('ops', { file: file.split('/').pop(), items: isArr ? data.length : null, bytes: Buffer.byteLength(JSON.stringify(data)) });
}

// --- Logs helpers ---
const logsFile = path.join(DATA_DIR, 'logs.json');
function readLogs(){
  try { return JSON.parse(fs.readFileSync(logsFile,'utf8')); } catch { return []; }
}
function appendLog(entry){
  const list = readLogs();
  list.push({
    time: new Date().toISOString(),
    level: entry.level || 'info',
    type: entry.type || 'event',
    message: entry.message || '',
    meta: entry.meta || null
  });
  fs.writeFileSync(logsFile, JSON.stringify(list.slice(-5000), null, 2));
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

function logError(context, e){
  const msg = (e && (e.message || e)) || 'Unknown error';
  pushLog('err', { context, error: String(msg) });
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

function readContacts() {
  return readJSON(contactsFile, []);
}
function writeContacts(list) {
  writeJSON(contactsFile, list);
}
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

  // Env-based emergency owner access
  if (OWNER_TG_ID && String(telegramId) === String(OWNER_TG_ID)) {
    return { role: 'owner', telegramId, provided: true, admin: { id: telegramId, role: 'owner', username: 'env_owner' } };
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

  pushLog('req', { method: req.method, path: pathname, role: ctx.role, tg: ctx.telegramId || null });

  try {
    if (pathname === '/api/health' && req.method === 'GET') {
      const counts = {
        groups: (readJSON(groupsFile, []) || []).length,
        services: (readJSON(servicesFile, []) || []).length,
        admins: (readJSON(adminsFile, []) || []).length,
        masters: (readJSON(mastersFile, []) || []).length,
        bookings: (readJSON(bookingsFile, []) || []).length,
        contacts: (readJSON(contactsFile, []) || []).length
      };
      sendJSON(res, 200, {
        ok: true,
        time: new Date().toISOString(),
        uptimeSec: Math.floor(process.uptime()),
        version: process.env.APP_VERSION || 'v13',
        counts
      });
      return;
    }

// Deep link helper: open admin with Telegram ID (used from /beauty command reply)
if (pathname === '/beauty' && req.method === 'GET') {
  // Если открыто в Telegram — admin.html сам возьмёт id из initDataUnsafe.
  // Фоллбек: ?tg_id=... — бот подставит ID.
  const tid = (query && query.tg_id) ? String(query.tg_id) : '';
  if (tid) {
    // сохраняем ID на 12 часов для последующих XHR из админки
    setCookie(res, 'tg_id', tid, { maxAge: 60*60*12 });
  }
  const url = tid ? `/admin?tg_id=${encodeURIComponent(tid)}` : '/admin';
  res.statusCode = 302; res.setHeader('Location', url); res.end();
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
    // GET /api/logs?limit=100
if (pathname === '/api/logs' && req.method === 'GET') {
  const limit = Math.max(1, Math.min(500, Number(new URL(req.url, 'http://x').searchParams.get('limit') || 100)));
  const logs = readLogs().slice(-limit);
  sendJSON(res, 200, { logs });
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

    // ==== Global API guard for mutations and sensitive reads ====
if (pathname.startsWith('/api/')) {
  const isWrite = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method);
  const protectedPrefixes = ['/api/services', '/api/groups', '/api/masters', '/api/backup'];
  const sensitiveReads   = ['/api/admins'];

  const needsAuth = (isWrite && protectedPrefixes.some(p => pathname.startsWith(p))) || sensitiveReads.includes(pathname);

  if (needsAuth) {
    const auth = getAdminAuth(req);
    if (!auth.authenticated) {
      return sendJSON(res, 401, { error: 'Unauthorized' });
    }
    // Управление администраторами — только для владельца
    if (pathname.startsWith('/api/admins') && req.method !== 'GET') {
      if ((auth.admin?.role || 'admin') !== 'owner') {
        return sendJSON(res, 403, { error: 'Only the owner can modify admins' });
      }
    }
  }
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

      // Always persist client contact (even if not coming from Telegram WebApp)
      try {
        const rawPhone = String(payload.clientPhone||'').trim();
        const digits = rawPhone.replace(/\D/g,'');
        const contactId = ctx.telegramId || (digits ? `phone:${digits}` : `anon:${Date.now()}`);
        const nameParts = String(payload.clientName||'').trim().split(/\s+/);
        upsertContact({
          id: contactId,
          first_name: nameParts[0] || undefined,
          last_name: nameParts.length > 1 ? nameParts.slice(1).join(' ') : undefined,
          phone: rawPhone || undefined
        });
      } catch {}

      // If opened as Telegram WebApp: link by numeric tg_id and notify via Telegram
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
          // Variant A: пришли с tg_id — зафиксируем cookie, чтобы API-запросы видели ID
  if (query && query.tg_id) {
    const qid = String(query.tg_id);
    if (qid) setCookie(res, 'tg_id', qid, { maxAge: 60*60*12 });
  }
      const admins = readAdmins();
      const candidateId = ctx.telegramId ?? (query && Number(query.tg_id)) ?? null;

      // Bootstrap: if admins.json is empty and we have a candidate ID, promote as owner
      if (Array.isArray(admins) && admins.length === 0 && Number.isFinite(candidateId)) {
        const seeded = { id: candidateId, username: 'owner', displayName: 'Owner', role: 'owner' };
        writeAdmins([seeded]);
      }

      // Re-evaluate after potential bootstrap
      const nowAdmins = readAdmins();
      const isAdmin = nowAdmins.some(a => a.id === candidateId);

      if (!isAdmin) {
        const bootstrap = `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Авторизация…</title><style>html,body{height:100%}body{margin:0;display:grid;place-items:center;background:#f6f7fb;font-family:system-ui,-apple-system,Segoe UI,Inter,sans-serif;color:#111827}section{background:#fff;border:1px solid rgba(209,213,219,.5);border-radius:14px;padding:22px;max-width:720px;text-align:center;display:grid;gap:10px}</style></head><body><section><h1>Авторизация через Telegram…</h1><p class="muted">Если вы открыли эту страницу <b>внутри Telegram</b>, мы попробуем авторизовать вас автоматически.</p><p class="muted">Если страница не обновится в течение 3 секунд, откройте админку из бота командой <b>/beauty</b>.</p></section><script>
(function(){
  function done(ok){ if(ok){ location.replace('/admin'); } else { document.body.innerHTML = '<section><h1>403</h1><p>Доступ ограничен. Откройте админку из Telegram: /beauty</p></section>'; } }
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
         } else if (/^\/beauty\b/.test(text)) {
           const url = `${PUBLIC_BASE_URL}/beauty?tg_id=${userId}`;
           await tgSendMessage(chatId, `🧿 <b>Вход в админку</b>\nОткройте ссылку внутри Telegram — доступ по вашему ID.\n${url}`, {
             reply_markup: {
               inline_keyboard: [ [ { text: 'Открыть админку', web_app: { url } } ] ]
             }
           });
         } else {
           await tgSendMessage(chatId, 'Не знаю эту команду. Попробуйте записаться по телефону или нажмите кнопку «Записаться» ниже.', {
             reply_markup: {
               inline_keyboard: [ [ { text: '🧾 Записаться', web_app: { url: `${PUBLIC_BASE_URL}/client` } } ] ]
             }
           });
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
        // 1) Prefer Railway env variable webhook if present
        const webhookUrl = process.env.GS_WEBHOOK_URL || process.env.webhookUrl || '';
        if (webhookUrl) {
          const load = (file, fallback=[]) => { try { return readJSON(file, fallback); } catch { return fallback; } };
          const mastersData = load(mastersFile, []);
          const payload = {
            groups:       load(groupsFile, []),
            services:     load(servicesFile, []),
            admins:       load(adminsFile, []),
            masters:      mastersData,              // каталог мастеров
            staffMasters: mastersData,              // дублируем для GS (лист StaffMasters)
            bookings:     load(bookingsFile, []),
            contacts:     load(contactsFile, []),
            hostes:       load(hostesFile, [])
          };

          const resp = await fetch(webhookUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
          });
          const text = await resp.text();
          if (!resp.ok) return sendJSON(res, 502, { error: `GS webhook export failed`, details: text });
          return sendJSON(res, 200, { status: 'ok', mode: 'webhook', response: text });
        }

        // 2) Fallback: direct Google Sheets API (service account)
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

        sendJSON(res, 200, { status: 'ok', mode: 'sheets', updated: 'Sheets updated' });
      } catch (e) {
        logError('gs_export', e);
        sendJSON(res, 500, { error: String(e.message || e) });
      }
      return;
    }

    if (pathname === '/api/gs/import' && req.method === 'POST') {
      if (!ensureAuthorized(ctx, res, ['admin'])) return;
      try {
        // 1) Prefer webhook JSON import (Apps Script doGet)
        const webhookUrl = process.env.GS_WEBHOOK_URL || process.env.webhookUrl || '';
        if (webhookUrl) {
          const url = webhookUrl.includes('?') ? `${webhookUrl}&mode=export_json` : `${webhookUrl}?mode=export_json`;
          const resp = await fetch(url, { method: 'GET', headers: { 'Accept': 'application/json' } });
          const text = await resp.text();
          if (!resp.ok) {
            return sendJSON(res, 502, { error: 'GS webhook import failed', details: text });
          }
          let data;

          try {
  data = JSON.parse(text);
  // Если внутри есть свойство 'data' или 'payload' — используем его
  if (data && typeof data === 'object' && (data.data || data.payload)) {
    data = data.data || data.payload;
  }
} catch (e) {
  console.error('❌ Ошибка разбора JSON из Google Script:', e, text.slice(0,3000));
  return sendJSON(res, 502, { error: 'GS webhook returned invalid JSON', details: text.slice(0,3000) });
}
          // Normalize payload structure and keys (accept several variants/cases)
          const src = (data && (data.data || data.payload)) ? (data.data || data.payload) : data;

          // --- Normalizers to coerce types and fill required fields ---
          const toInt = (v, d=null) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
          const toStr = (v, d='') => (v==null ? d : String(v));
          const toArr = (v) => Array.isArray(v) ? v : [];

          function normGroup(g){
            return { id: toInt(g.id, Date.now()), name: toStr(g.name).trim() };
          }
          function normService(s){
            return {
              id: toInt(s.id, Date.now()),
              name: toStr(s.name).trim(),
              description: toStr(s.description,''),
              price: toInt(s.price, 0),
              duration: toInt(s.duration, 30),
              groupId: s.groupId===''||s.groupId==null ? null : toInt(s.groupId, null)
            };
          }
          function normAdmin(a){
            const role = a.role==='owner' ? 'owner' : 'admin';
            const id = toInt(a.id, 0);
            const username = toStr(a.username).replace(/^@/, '').trim();
            return id>0 && username ? { id, username, displayName: toStr(a.displayName||a.name||username), role } : null;
          }
          function normMaster(m){
            const id = toInt(m.id, Date.now());
            const name = toStr(m.name).trim();
            const specialties = toStr(m.specialties,'').split(',').map(x=>x.trim()).filter(Boolean);
            const serviceIds = toStr(m.serviceIds,'').split(',').map(x=>toInt(x)).filter(Number.isFinite);
            let schedule = null; try { schedule = m.schedule || (m.schedule_json ? JSON.parse(m.schedule_json) : null); } catch {}
            return { id, name, specialties, photoUrl: m.photoUrl||null, description: toStr(m.description,''), schedule, serviceIds };
          }
          function normBooking(b){
            // Require minimal fields: date, startTime, serviceId
            const date = toStr(b.date).trim();
            const startTime = toStr(b.startTime).trim();
            const serviceId = toInt(b.serviceId, null);
            if (!date || !startTime || !Number.isFinite(serviceId)) return null;
            const id = toInt(b.id, Date.now());
            const status = toStr(b.status||'pending');
            const clientName = toStr(b.clientName||'');
            const clientPhone = toStr(b.clientPhone||'');
            const notes = toStr(b.notes||'');
            const serviceName = toStr(b.serviceName||'');
            const serviceDuration = toInt(b.serviceDuration, null);
            const servicePrice = toInt(b.servicePrice, null);
            const masterId = (b.masterId===''||b.masterId==null) ? null : toStr(b.masterId);
            const duration = toInt(b.duration, serviceDuration); // keep if provided
            const createdAt = toStr(b.createdAt||new Date().toISOString());
            const updatedAt = toStr(b.updatedAt||createdAt);
            return { id, createdAt, updatedAt, status, clientName, clientPhone, notes, serviceId, serviceName, serviceDuration, servicePrice, masterId, date, startTime, duration };
          }

          // Map keys from payload (support multiple cases)
          const pickArray = (...keys) => {
            for (const k of keys) { const v = src[k]; if (Array.isArray(v)) return v; }
            for (const k of keys) { const v = src[k]; if (v && Array.isArray(v.values)) return v.values; }
            return [];
          };
          const hasAnyKey = (...keys) => keys.some(k => Object.prototype.hasOwnProperty.call(src, k));

          const rawGroups   = pickArray('groups','Groups');
          const rawServices = pickArray('services','Services');
          const rawAdmins   = pickArray('admins','Admins');
          const rawMasters  = pickArray('masters','Masters','staffMasters','StaffMasters');
          const rawBookings = pickArray('bookings','Bookings');
          const rawContacts = pickArray('contacts','Contacts');
          const rawHostes   = pickArray('hostes','Hostes');

          const groups   = toArr(rawGroups).map(normGroup).filter(g=>g.name);
          const services = toArr(rawServices).map(normService).filter(s=>s.name);
          const admins   = toArr(rawAdmins).map(normAdmin).filter(Boolean);
          const masters  = toArr(rawMasters).map(normMaster).filter(m=>m.name);
          const bookings = toArr(rawBookings).map(normBooking).filter(Boolean);
          const contacts = toArr(rawContacts); // passthrough
          const hostes   = toArr(rawHostes);   // passthrough

          if (hasAnyKey('groups','Groups'))         writeJSON(groupsFile,   groups);
          if (hasAnyKey('services','Services'))     writeJSON(servicesFile, services);
          if (hasAnyKey('admins','Admins'))         writeJSON(adminsFile,   admins);
          if (hasAnyKey('masters','Masters','staffMasters','StaffMasters')) writeJSON(mastersFile,  masters);
          if (hasAnyKey('bookings','Bookings'))     writeJSON(bookingsFile, bookings);
          if (hasAnyKey('contacts','Contacts'))     writeJSON(contactsFile, contacts);
          if (hasAnyKey('hostes','Hostes'))         writeJSON(hostesFile,   hostes);

          console.log('GS webhook import (normalized) wrote:', {
            groups: groups.length,
            services: services.length,
            admins: admins.length,
            masters: masters.length,
            bookings: bookings.length,
            contacts: contacts.length,
            hostes: hostes.length
          });

          return sendJSON(res, 200, { status: 'ok', mode: 'webhook', imported: {
            groups: groups.length,
            services: services.length,
            admins: admins.length,
            masters: masters.length,
            bookings: bookings.length,
            contacts: contacts.length,
            hostes: hostes.length
          } });
        }

        // 2) Fallback: direct Google Sheets API (requires GOOGLE_SERVICE_ACCOUNT_JSON)
        if (!GOOGLE_SERVICE_ACCOUNT_JSON) {
          return sendJSON(res, 400, { error: 'GOOGLE_SERVICE_ACCOUNT_JSON not set; configure GS_WEBHOOK_URL or service account to import' });
        }

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
            const obj = {}; headersExpected.forEach((h)=>{ obj[h] = r[idx[h]] ?? ''; }); return obj;
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

        sendJSON(res, 200, { status: 'ok', mode: 'sheets', imported: { groups: groups.length, services: services.length, admins: admins.length, masters: masters.length, bookings: bookings.length } });
      } catch (e) {
        logError('gs_import', e);
        sendJSON(res, 500, { error: String(e.message || e) });
      }
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
              try { appendLog({ type: 'backup.export', message: 'Экспорт ZIP выполнен' }); } catch {}
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
            try { appendLog({ type: 'backup.import', message: 'Импорт ZIP выполнен' }); } catch {}
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
    <!-- View switcher -->
    <div class="views">
      <button class="chip active" data-view="day">День</button>
      <button class="chip" data-view="week">Неделя</button>
      <button class="chip" data-view="month">Месяц</button>
      <button class="chip" data-view="list">Список</button>
    </div>
    <!-- Day scroller -->
    <div class="days" id="days"></div>
    <div class="sel-date" id="selDate"></div>
    <!-- Timeline -->
    <div class="timeline" id="timeline">
      <div class="events" id="events"></div>
    </div>
    <!-- Bottom nav -->
    <nav class="nav">
      <a href="#" class="active"><div class="dot">📄</div><span>Записи</span></a>
      <a href="/manager?schedule"><div class="dot">📆</div><span>График</span></a>
      <a href="/admin"><div class="dot">🛠</div><span>Управление</span></a>
      <a href="/health"><div class="dot">⚙️</div><span>Настройки</span></a>
    </nav>
  </div>
  <button class="fab" id="fab" title="Добавить запись">+</button>

  <script>
    // --- Utils ---
    const pad = n => String(n).padStart(2,'0');
    const toISO = d => d.toISOString().slice(0,10);
    const fmtRu = d => d.toLocaleDateString('ru-RU',{weekday:'long',day:'numeric',month:'long',year:'numeric'});

    let state = {
      date: toISO(new Date()),
      open: 9*60, close: 21*60, step: 60, // fallback
      bookings: []
    };

    init();

    async function init(){
      renderDayStrip();
      await loadMeta();     // get business hours/slots
      await loadBookings(); // admin-only; silently ignore if forbidden
      renderAll();
      document.getElementById('fab').onclick = ()=> location.href='/client';
      document.querySelectorAll('.chip').forEach(b=>b.onclick = onChangeView);
    }

    function onChangeView(e){
      const v = e.currentTarget.dataset.view;
      document.querySelectorAll('.chip').forEach(x=>x.classList.toggle('active', x.dataset.view===v));
      // Пока реализован только вид "День"
    }

    function renderDayStrip(anchor = new Date(state.date)){
      const daysEl = document.getElementById('days');
      daysEl.innerHTML = '';
      for(let i=-4;i<=4;i++){
        const d = new Date(anchor); d.setDate(d.getDate()+i);
        const iso = toISO(d);
        const el = document.createElement('div');
        el.className = 'day'+(iso===state.date?' active':'');
        el.innerHTML = '<div class="dow">'+d.toLocaleDateString('ru-RU',{weekday:'short'})+'</div>'+
                       '<div><b>'+d.getDate()+'</b> '+d.toLocaleDateString('ru-RU',{month:'short'})+'</div>';
        el.onclick = ()=>{ state.date = iso; onDateChange(); };
        daysEl.appendChild(el);
      }
      document.getElementById('selDate').textContent = 'Выбрано: '+fmtRu(new Date(state.date));
    }

    async function onDateChange(){
      renderDayStrip();
      await loadBookings();
      renderAll();
    }

    function renderAll(){
      renderTimelineGrid();
      renderEvents();
    }

    function renderTimelineGrid(){
      const wrap = document.getElementById('timeline');
      wrap.querySelectorAll('.hour').forEach(n=>n.remove());
      const hoursCount = Math.ceil((state.close - state.open)/60);
      for(let h=0; h<=hoursCount; h++){
        const m = state.open + h*60;
        const label = pad(Math.floor(m/60))+':'+pad(m%60);
        const row = document.createElement('div');
        row.className = 'hour';
        row.style.top = (h*64)+'px';
        const lab = document.createElement('div'); lab.className='label'; lab.textContent = label;
        row.appendChild(lab);
        wrap.appendChild(row);
      }
      wrap.style.setProperty('--hours', hoursCount+1);
      wrap.style.height = Math.max(420, (hoursCount+1)*64)+'px';
      document.getElementById('selDate').textContent = 'Выбрано: '+fmtRu(new Date(state.date));
    }

    function renderEvents(){
      const ev = document.getElementById('events');
      ev.innerHTML = '';
      const dayStart = state.open;
      const pxPerMin = 64/60;
      state.bookings.forEach(b=>{
        const start = toMin(b.startTime);
        const dur = Number(b.duration)||state.step;
        const top = ( (start - dayStart) * pxPerMin );
        const height = dur * pxPerMin;
        if (height <= 0) return;
        const el = document.createElement('div');
        el.className='booking';
        el.style.top = Math.max(0, top)+'px';
        el.style.height = height+'px';
        el.innerHTML = '<div class="title">'+(b.serviceName||'Услуга')+'</div>'
                     + '<div>'+ (b.clientName||'Клиент') +'</div>'
                     + '<div>'+ b.startTime +' · '+ dur +' мин</div>';
        ev.appendChild(el);
      });
    }

    function toMin(t){
      const [hh,mm] = String(t).split(':').map(Number);
      return hh*60 + (mm||0);
    }

    async function loadMeta(){
      try{
        const r = await fetch('/api/availability?date='+encodeURIComponent(state.date));
        if(!r.ok) return;
        const j = await r.json();
        const meta = j.meta || {};
        if (meta.businessHours){
          state.open = toMin(meta.businessHours.open || '09:00');
          state.close = toMin(meta.businessHours.close || '21:00');
        }
        state.step = Number(meta.slotStep||60);
      }catch(e){}
    }

    async function loadBookings(){
      state.bookings = [];
      try{
        const r = await fetch('/api/bookings?date='+encodeURIComponent(state.date));
        if(!r.ok) return;
        state.bookings = await r.json();
      }catch(e){}
    }
  </script>
</body>
</html>
EOF

# --- client.html ---
cat <<'EOF' > public/client.html
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
            <input type="text" id="clientName" placeholder="Имя" required />
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
    .fab{position:fixed;right:18px;bottom:84px;width:56px;height:56px;border-radius:50%;background:#007aff;color:#fff;display:flex;align-items:center;justify-content:center;font-size:28px;line-height:0;border:none;box-shadow:0 16px 36px -16px rgba(0,122,255,.5);cursor:pointer}
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
