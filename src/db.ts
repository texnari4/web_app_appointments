import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export type Master = {
  id: string;
  name: string;
  phone: string;
  avatarUrl?: string;
  isActive: boolean;
  description?: string;
  specialties?: string[];
  schedule?: { daysOfWeek?: number[]; custom?: Array<{ from: string; to: string }>; };
  createdAt: string;
  updatedAt: string;
};

export type Service = {
  id: string;
  groupId: string; // e.g. "nails", "hair"
  title: string;
  description?: string;
  price: number;
  durationMin: number;
  createdAt: string;
  updatedAt: string;
};

export type ServiceGroup = {
  id: string;
  name: string; // e.g. "Ногтевой сервис"
  order?: number;
  createdAt: string;
  updatedAt: string;
};

type DbShape = {
  masters: Master[];
  services: Service[];
  serviceGroups: ServiceGroup[];
  clients: any[];
  bookings: any[];
};

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

async function ensureFile(): Promise<void> {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    const now = new Date().toISOString();
    const seed: DbShape = {
      masters: [
        {
          id: crypto.randomUUID(), name: 'Юлия', phone: '+375331126113',
          avatarUrl: 'https://placehold.co/100x100', isActive: true,
          description: 'Мастер маникюра', specialties: ['маникюр', 'педикюр'],
          schedule: { daysOfWeek: [1,2,3,4,5] },
          createdAt: now, updatedAt: now
        }
      ],
      serviceGroups: [
        { id: 'nails', name: 'Ногтевой сервис', order: 1, createdAt: now, updatedAt: now },
        { id: 'hair', name: 'Волосы', order: 2, createdAt: now, updatedAt: now }
      ],
      services: [
        { id: crypto.randomUUID(), groupId: 'nails', title: 'Маникюр классический', price: 25, durationMin: 60, createdAt: now, updatedAt: now },
        { id: crypto.randomUUID(), groupId: 'nails', title: 'Покрытие гель-лаком', price: 30, durationMin: 50, createdAt: now, updatedAt: now },
        { id: crypto.randomUUID(), groupId: 'hair', title: 'Стрижка женская', price: 40, durationMin: 60, createdAt: now, updatedAt: now }
      ],
      clients: [],
      bookings: []
    };
    await fs.writeFile(DB_FILE, JSON.stringify(seed, null, 2), 'utf-8');
  }
}

async function readDb(): Promise<DbShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf-8');
  return JSON.parse(raw) as DbShape;
}
async function writeDb(db: DbShape): Promise<void> {
  await ensureFile();
  await fs.writeFile(DB_FILE, JSON.stringify(db, null, 2), 'utf-8');
}

// Masters
export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}
export async function createMaster(input: Omit<Master, 'id' | 'createdAt' | 'updatedAt'>): Promise<Master> {
  const db = await readDb();
  const now = new Date().toISOString();
  const item: Master = { id: crypto.randomUUID(), createdAt: now, updatedAt: now, ...input };
  db.masters.push(item);
  await writeDb(db);
  return item;
}
export async function updateMaster(id: string, patch: Partial<Master>): Promise<Master | null> {
  const db = await readDb();
  const idx = db.masters.findIndex(m => m.id === id);
  if (idx === -1) return null;
  db.masters[idx] = { ...db.masters[idx], ...patch, updatedAt: new Date().toISOString() };
  await writeDb(db);
  return db.masters[idx];
}
export async function deleteMaster(id: string): Promise<boolean> {
  const db = await readDb();
  const prev = db.masters.length;
  db.masters = db.masters.filter(m => m.id !== id);
  await writeDb(db);
  return db.masters.length < prev;
}

// Service Groups
export async function listServiceGroups(): Promise<ServiceGroup[]> {
  const db = await readDb();
  return db.serviceGroups.sort((a,b) => (a.order ?? 999) - (b.order ?? 999));
}
export async function upsertServiceGroup(g: Partial<ServiceGroup> & { name: string }): Promise<ServiceGroup> {
  const db = await readDb();
  const now = new Date().toISOString();
  if (g.id) {
    const idx = db.serviceGroups.findIndex(x => x.id === g.id);
    if (idx !== -1) {
      db.serviceGroups[idx] = { ...db.serviceGroups[idx], ...g, updatedAt: now };
      await writeDb(db);
      return db.serviceGroups[idx];
    }
  }
  const created: ServiceGroup = { id: g.id ?? crypto.randomUUID(), name: g.name, order: g.order ?? 999, createdAt: now, updatedAt: now };
  db.serviceGroups.push(created);
  await writeDb(db);
  return created;
}
export async function deleteServiceGroup(id: string): Promise<boolean> {
  const db = await readDb();
  const prev = db.serviceGroups.length;
  db.serviceGroups = db.serviceGroups.filter(sg => sg.id !== id);
  // also detach services
  db.services = db.services.filter(s => s.groupId !== id);
  await writeDb(db);
  return db.serviceGroups.length < prev;
}

// Services
export async function listServices(): Promise<Service[]> {
  const db = await readDb();
  return db.services;
}
export async function createService(input: Omit<Service, 'id' | 'createdAt' | 'updatedAt'>): Promise<Service> {
  const db = await readDb();
  const now = new Date().toISOString();
  const item: Service = { id: crypto.randomUUID(), createdAt: now, updatedAt: now, ...input };
  db.services.push(item);
  await writeDb(db);
  return item;
}
export async function updateService(id: string, patch: Partial<Service>): Promise<Service | null> {
  const db = await readDb();
  const idx = db.services.findIndex(s => s.id === id);
  if (idx === -1) return null;
  db.services[idx] = { ...db.services[idx], ...patch, updatedAt: new Date().toISOString() };
  await writeDb(db);
  return db.services[idx];
}
export async function deleteService(id: string): Promise<boolean> {
  const db = await readDb();
  const prev = db.services.length;
  db.services = db.services.filter(s => s.id !== id);
  await writeDb(db);
  return db.services.length < prev;
}
