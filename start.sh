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
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { parse } from 'url';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(__dirname, 'data');
mkdirSync(DATA_DIR, { recursive: true });

const servicesFile = join(DATA_DIR, 'services.json');
const groupsFile = join(DATA_DIR, 'groups.json');
const bookingsFile = join(DATA_DIR, 'bookings.json');
const adminsFile = join(DATA_DIR, 'admins.json');

const SLOT_STEP_MIN = Number(process.env.SLOT_STEP_MIN || 30);
const BUSINESS_OPEN_TIME = process.env.BUSINESS_OPEN_TIME || '09:00';
const BUSINESS_CLOSE_TIME = process.env.BUSINESS_CLOSE_TIME || '21:00';

const DEFAULT_GROUPS = [
  { id: 1, name: 'Массаж' },
  { id: 2, name: 'Парикмахерские услуги' },
  { id: 3, name: 'Ногтевой сервис' }
];

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

function sendJSON(res, statusCode, payload) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function sendText(res, statusCode, payload) {
  res.writeHead(statusCode, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(payload);
}

const ROLE_WEIGHT = {
  unknown: -1,
  guest: 0,
  admin: 2,
  owner: 3
};

function parseTelegramId(req) {
  const headerId = req.headers['x-telegram-id'] ?? req.headers['x-telegram-user-id'];
  if (headerId != null) {
    const numeric = Number(headerId);
    if (Number.isFinite(numeric)) {
      return numeric;
    }
  }

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
      sendText(res, 200, 'OK');
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

    if (pathname === '/admin' || pathname === '/admin/' || pathname.startsWith('/admin')) {
      const html = readFileSync(join(__dirname, 'public', 'admin.html'), 'utf-8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
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

# --- admin.html ---
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

echo ">>> Запуск сервера..."
npm start
