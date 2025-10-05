import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const dataDir = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const dbFile = path.join(dataDir, 'db.json');

type Master = {
  id: string;
  name: string;
  phone?: string;
  avatarUrl?: string;
  description?: string;
  specialties?: string[];
  schedule?: {
    mode: 'weekly' | 'custom';
    weekly?: { // weekly mode
      monday: boolean; tuesday: boolean; wednesday: boolean; thursday: boolean; friday: boolean; saturday: boolean; sunday: boolean;
      hours?: { start: string; end: string };
    };
    custom?: Array<{ date: string; start: string; end: string }>; // ISO date items
  };
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

type Service = {
  id: string;
  name: string;
  description?: string;
  price: number;
  durationMin: number;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

type Client = {
  id: string;
  name: string;
  phone?: string;
  tg?: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
};

type Appointment = {
  id: string;
  masterId: string;
  serviceId: string;
  clientId: string;
  start: string; // ISO
  end: string; // ISO
  price?: number;
  status: 'new' | 'confirmed' | 'done' | 'cancelled';
  createdAt: string;
  updatedAt: string;
};

type Database = {
  masters: Master[];
  services: Service[];
  clients: Client[];
  appointments: Appointment[];
};

async function ensureFile(): Promise<void> {
  await fs.mkdir(dataDir, { recursive: true });
  try {
    await fs.access(dbFile);
  } catch {
    const initial: Database = { masters: [], services: [], clients: [], appointments: [] };
    await fs.writeFile(dbFile, JSON.stringify(initial, null, 2), 'utf-8');
  }
}

async function readDb(): Promise<Database> {
  await ensureFile();
  const raw = await fs.readFile(dbFile, 'utf-8');
  return JSON.parse(raw) as Database;
}

async function writeDb(db: Database): Promise<void> {
  await ensureFile();
  const tmp = dbFile + '.tmp';
  await fs.writeFile(tmp, JSON.stringify(db, null, 2), 'utf-8');
  await fs.rename(tmp, dbFile);
}

// Helpers
const now = () => new Date().toISOString();
const uuid = () => crypto.randomUUID();

// Masters
export async function listMasters() {
  const db = await readDb();
  return db.masters;
}
export async function addMaster(payload: Partial<Master>) {
  const db = await readDb();
  const item: Master = {
    id: uuid(),
    name: payload.name || 'Без имени',
    phone: payload.phone,
    avatarUrl: payload.avatarUrl,
    description: payload.description,
    specialties: payload.specialties ?? [],
    schedule: payload.schedule ?? { mode: 'weekly', weekly: { monday: true, tuesday: true, wednesday: true, thursday: true, friday: true, saturday: false, sunday: false, hours: { start: '09:00', end: '18:00' } } },
    isActive: payload.isActive ?? true,
    createdAt: now(),
    updatedAt: now(),
  };
  db.masters.unshift(item);
  await writeDb(db);
  return item;
}
export async function updateMaster(id: string, patch: Partial<Master>) {
  const db = await readDb();
  const idx = db.masters.findIndex(m => m.id === id);
  if (idx === -1) return null;
  db.masters[idx] = { ...db.masters[idx], ...patch, id, updatedAt: now() };
  await writeDb(db);
  return db.masters[idx];
}
export async function removeMaster(id: string) {
  const db = await readDb();
  const before = db.masters.length;
  db.masters = db.masters.filter(m => m.id !== id);
  await writeDb(db);
  return before !== db.masters.length;
}

// Services
export async function listServices() {
  const db = await readDb();
  return db.services;
}
export async function addService(payload: Partial<Service>) {
  const db = await readDb();
  const item: Service = {
    id: uuid(),
    name: payload.name || 'Новая услуга',
    description: payload.description,
    price: typeof payload.price === 'number' ? payload.price : 0,
    durationMin: typeof payload.durationMin === 'number' ? payload.durationMin : 60,
    isActive: payload.isActive ?? True, // will fix later if needed
    createdAt: now(),
    updatedAt: now(),
  };
  db.services.unshift(item);
  await writeDb(db);
  return item;
}
export async function updateService(id: string, patch: Partial<Service>) {
  const db = await readDb();
  const idx = db.services.findIndex(s => s.id === id);
  if (idx === -1) return null;
  db.services[idx] = { ...db.services[idx], ...patch, id, updatedAt: now() };
  await writeDb(db);
  return db.services[idx];
}
export async function removeService(id: string) {
  const db = await readDb();
  const before = db.services.length;
  db.services = db.services.filter(s => s.id !== id);
  await writeDb(db);
  return before !== db.services.length;
}

// Clients
export async function listClients(query?: string) {
  const db = await readDb();
  const items = db.clients;
  if (!query) return items;
  const q = query.toLowerCase();
  return items.filter(c => (c.name?.toLowerCase().includes(q) || c.phone?.toLowerCase().includes(q)));
}
export async function addClient(payload: Partial<Client>) {
  const db = await readDb();
  const item: Client = {
    id: uuid(),
    name: payload.name || 'Новый клиент',
    phone: payload.phone,
    tg: payload.tg,
    notes: payload.notes,
    createdAt: now(),
    updatedAt: now(),
  };
  db.clients.unshift(item);
  await writeDb(db);
  return item;
}
export async function updateClient(id: string, patch: Partial<Client>) {
  const db = await readDb();
  const idx = db.clients.findIndex(c => c.id === id);
  if (idx === -1) return null;
  db.clients[idx] = { ...db.clients[idx], ...patch, id, updatedAt: now() };
  await writeDb(db);
  return db.clients[idx];
}
export async function removeClient(id: string) {
  const db = await readDb();
  const before = db.clients.length;
  db.clients = db.clients.filter(c => c.id !== id);
  await writeDb(db);
  return before !== db.clients.length;
}

// Appointments
export async function listAppointments(filters?: { from?: string; to?: string; masterId?: string; clientId?: string; serviceId?: string; }) {
  const db = await readDb();
  let items = db.appointments;
  if (filters?.from) items = items.filter(a => a.start >= filters.from!);
  if (filters?.to) items = items.filter(a => a.start <= filters.to!);
  if (filters?.masterId) items = items.filter(a => a.masterId === filters.masterId);
  if (filters?.clientId) items = items.filter(a => a.clientId === filters.clientId);
  if (filters?.serviceId) items = items.filter(a => a.serviceId === filters.serviceId);
  return items;
}
export async function addAppointment(payload: Partial<Appointment>) {
  const db = await readDb();
  const item: Appointment = {
    id: uuid(),
    masterId: payload.masterId!,
    serviceId: payload.serviceId!,
    clientId: payload.clientId!,
    start: payload.start!,
    end: payload.end!,
    price: payload.price,
    status: (payload.status as Appointment['status']) ?? 'new',
    createdAt: now(),
    updatedAt: now(),
  };
  db.appointments.unshift(item);
  await writeDb(db);
  return item;
}
export async function updateAppointment(id: string, patch: Partial<Appointment>) {
  const db = await readDb();
  const idx = db.appointments.findIndex(a => a.id === id);
  if (idx === -1) return null;
  db.appointments[idx] = { ...db.appointments[idx], ...patch, id, updatedAt: now() };
  await writeDb(db);
  return db.appointments[idx];
}
export async function removeAppointment(id: string) {
  const db = await readDb();
  const before = db.appointments.length;
  db.appointments = db.appointments.filter(a => a.id !== id);
  await writeDb(db);
  return before !== db.appointments.length;
}

// Reports
export async function report(from: string, to: string) {
  const db = await readDb();
  const inRange = db.appointments.filter(a => a.start >= from && a.start <= to && a.status !== 'cancelled');
  const income = inRange.reduce((sum, a) => sum + (a.price ?? 0), 0);
  const byService = new Map<string, number>();
  for (const a of inRange) {
    byService.set(a.serviceId, (byService.get(a.serviceId) ?? 0) + 1);
  }
  const topServices = [...byService.entries()].sort((a,b)=>b[1]-a[1]).slice(0,10).map(([serviceId, count]) => ({ serviceId, count }));
  return { from, to, totalAppointments: inRange.length, income, topServices };
}