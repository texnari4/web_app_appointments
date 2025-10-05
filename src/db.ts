import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

export type ID = string;
export type ISO = string;

export interface Master {
  id: ID;
  name: string;
  phone?: string;
  avatarUrl?: string;
  description?: string;
  specialties?: string[];
  schedule?: {"daysOfWeek": number[]};
  isActive: boolean;
  createdAt: ISO;
  updatedAt: ISO;
}

export interface ServiceGroup {
  id: ID;
  name: string;
  description?: string;
  createdAt: ISO;
  updatedAt: ISO;
}

export interface Service {
  id: ID;
  groupId: ID;
  name: string;
  description?: string;
  price: number;
  durationMin: number;
  createdAt: ISO;
  updatedAt: ISO;
}

export interface Client {
  id: ID;
  name: string;
  phone?: string;
  createdAt: ISO;
  updatedAt: ISO;
}

export interface Booking {
  id: ID;
  masterId: ID;
  clientId: ID;
  serviceId: ID;
  startsAt: ISO;
  endsAt: ISO;
  note?: string;
  createdAt: ISO;
  updatedAt: ISO;
}

export interface DB {
  masters: Master[];
  serviceGroups: ServiceGroup[];
  services: Service[];
  clients: Client[];
  bookings: Booking[];
  settings: Record<string, unknown>;
}

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_PATH = path.join(DATA_DIR, 'db.json');

async function ensureFile() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(DB_PATH);
  } catch { 
    await fs.writeFile(DB_PATH, JSON.stringify(defaultSeed(), null, 2));
    await fs.chmod(DB_PATH, 0o666).catch(() => {});
  }
}

export async function readDb(): Promise<DB> {
  await ensureFile();
  const raw = await fs.readFile(DB_PATH, 'utf8').catch(async () => { 
    await fs.writeFile(DB_PATH, JSON.stringify(defaultSeed(), null, 2));
    return JSON.stringify(defaultSeed());
  });
  try { 
    const parsed = JSON.parse(raw) as Partial<DB>;
    // If file exists but empty/invalid – reset
    if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.masters)) {
      const seed = defaultSeed();
      await fs.writeFile(DB_PATH, JSON.stringify(seed, null, 2));
      return seed;
    }
    return parsed as DB;
  } catch {
    const seed = defaultSeed();
    await fs.writeFile(DB_PATH, JSON.stringify(seed, null, 2));
    return seed;
  }
}

export async function writeDb(db: DB): Promise<void> {
  await ensureFile();
  await fs.writeFile(DB_PATH, JSON.stringify(db, null, 2));
}

export const nowISO = () => new Date().toISOString();
export const uid = () => crypto.randomUUID();

function defaultSeed(): DB {
  const t = nowISO();
  const groupId = uid();
  const masterId = uid();
  return {
    masters: [{
      id: masterId,
      name: 'Юлия',
      phone: '+375331126113',
      avatarUrl: 'https://picsum.photos/seed/master1/120/120',
      description: 'Мастер ногтевого сервиса',
      specialties: ['маникюр', 'педикюр'],
      schedule: { daysOfWeek: [1,2,3,4,5] },
      isActive: true,
      createdAt: t,
      updatedAt: t,
    }],
    serviceGroups: [{
      id: groupId,
      name: 'Ногтевой сервис',
      description: 'Маникюр и педикюр',
      createdAt: t,
      updatedAt: t
    }],
    services: [
      {
        id: uid(),
        groupId,
        name: 'Маникюр классический',
        description: 'Обработка ногтей и кутикулы',
        price: 25,
        durationMin: 60,
        createdAt: t,
        updatedAt: t,
      },
      {
        id: uid(),
        groupId,
        name: 'Покрытие гель-лак',
        description: 'Цветное покрытие с топом',
        price: 20,
        durationMin: 45,
        createdAt: t,
        updatedAt: t,
      }
    ],
    clients: [{ id: uid(), name: 'Анна', phone: '+375291234567', createdAt: t, updatedAt: t }],
    bookings: [],
    settings: {}
  };
}

// CRUD helpers
export async function listMasters() { return (await readDb()).masters; }
export async function createMaster(payload: Partial<Master>): Promise<Master> {
  const db = await readDb();
  const t = nowISO();
  const item: Master = {
    id: uid(),
    name: payload.name || 'Без имени',
    phone: payload.phone,
    avatarUrl: payload.avatarUrl,
    description: payload.description,
    specialties: payload.specialties ?? [],
    schedule: payload.schedule ?? { daysOfWeek: [1,2,3,4,5] },
    isActive: payload.isActive ?? true, // will be fixed in ts by using true literal
    createdAt: t,
    updatedAt: t,
  } as Master;
  db.masters.push(item);
  await writeDb(db);
  return item;
}

export async function updateMaster(id: ID, payload: Partial<Master>): Promise<Master | null> {
  const db = await readDb();
  const idx = db.masters.findIndex(m => m.id === id);
  if (idx === -1) return null;
  db.masters[idx] = { ...db.masters[idx], ...payload, updatedAt: nowISO() };
  await writeDb(db);
  return db.masters[idx];
}

export async function deleteMaster(id: ID): Promise<boolean> {
  const db = await readDb();
  const before = db.masters.length;
  db.masters = db.masters.filter(m => m.id !== id);
  await writeDb(db);
  return db.masters.length < before;
}

// Groups
export async function listServiceGroups() { return (await readDb()).serviceGroups; }
export async function createServiceGroup(payload: Partial<ServiceGroup>): Promise<ServiceGroup> {
  const db = await readDb();
  const t = nowISO();
  const item: ServiceGroup = {
    id: uid(),
    name: payload.name || 'Новая группа',
    description: payload.description,
    createdAt: t,
    updatedAt: t,
  };
  db.serviceGroups.push(item);
  await writeDb(db);
  return item;
}
export async function updateServiceGroup(id: ID, payload: Partial<ServiceGroup>) {
  const db = await readDb();
  const idx = db.serviceGroups.findIndex(g => g.id === id);
  if (idx === -1) return null;
  db.serviceGroups[idx] = { ...db.serviceGroups[idx], ...payload, updatedAt: nowISO() };
  await writeDb(db);
  return db.serviceGroups[idx];
}
export async function deleteServiceGroup(id: ID) {
  const db = await readDb();
  db.serviceGroups = db.serviceGroups.filter(g => g.id !== id);
  db.services = db.services.filter(s => s.groupId !== id);
  await writeDb(db);
  return true;
}

// Services
export async function listServices() { return (await readDb()).services; }
export async function createService(payload: Partial<Service>): Promise<Service> {
  const db = await readDb();
  const t = nowISO();
  const item: Service = {
    id: uid(),
    groupId: payload.groupId as ID,
    name: payload.name || 'Новая услуга',
    description: payload.description,
    price: Number(payload.price ?? 0),
    durationMin: Number(payload.durationMin ?? 30),
    createdAt: t,
    updatedAt: t,
  };
  db.services.push(item);
  await writeDb(db);
  return item;
}
export async function updateService(id: ID, payload: Partial<Service>) {
  const db = await readDb();
  const idx = db.services.findIndex(s => s.id === id);
  if (idx === -1) return null;
  db.services[idx] = { ...db.services[idx], ...payload, updatedAt: nowISO() };
  await writeDb(db);
  return db.services[idx];
}
export async function deleteService(id: ID) {
  const db = await readDb();
  db.services = db.services.filter(s => s.id !== id);
  await writeDb(db);
  return true;
}
