import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const DB_FILE = path.join(DATA_DIR, 'db.json');

type UUID = string;

export type Master = {
  id: UUID;
  name: string;
  phone: string;
  avatarUrl?: string;
  isActive: boolean;
  about?: string;
  specialties?: string[];
  schedule?: {
    mon?: boolean; tue?: boolean; wed?: boolean; thu?: boolean; fri?: boolean; sat?: boolean; sun?: boolean;
  };
  createdAt: string;
  updatedAt: string;
};

export type ServiceGroup = {
  id: UUID;
  title: string;
  description?: string;
  createdAt: string;
  updatedAt: string;
};

export type Service = {
  id: UUID;
  groupId: UUID;
  title: string;
  description?: string;
  price: number;
  durationMin: number;
  createdAt: string;
  updatedAt: string;
};

export type Client = {
  id: UUID;
  name: string;
  phone: string;
  createdAt: string;
  updatedAt: string;
};

type Db = {
  masters: Master[];
  serviceGroups: ServiceGroup[];
  services: Service[];
  clients: Client[];
};

async function ensureFile() {
  await mkdir(DATA_DIR, { recursive: true });
  try {
    await readFile(DB_FILE, 'utf-8');
  } catch {
    const now = new Date().toISOString();
    const seed: Db = {
      masters: [{
        id: crypto.randomUUID(),
        name: "Юлия",
        phone: "+375331126113",
        avatarUrl: "http://testurl.com",
        isActive: true,
        specialties: ["Ногтевой сервис"],
        createdAt: now,
        updatedAt: now
      }],
      serviceGroups: [{
        id: crypto.randomUUID(),
        title: "Ногтевой сервис",
        description: "Маникюр, покрытие, уход",
        createdAt: now,
        updatedAt: now
      }],
      services: [],
      clients: [{
        id: crypto.randomUUID(),
        name: "Тест Клиент",
        phone: "+375000000000",
        createdAt: now,
        updatedAt: now
      }]
    };
    await writeFile(DB_FILE, JSON.stringify(seed, null, 2), 'utf-8');
  }
}

async function readDb(): Promise<Db> {
  await ensureFile();
  const txt = await readFile(DB_FILE, 'utf-8');
  return JSON.parse(txt) as Db;
}

async function writeDb(db: Db): Promise<void> {
  await ensureFile();
  await writeFile(DB_FILE, JSON.stringify(db, null, 2), 'utf-8');
}

export const db = {
  async listMasters() {
    const d = await readDb();
    return d.masters;
  },
  async addMaster(input: Omit<Master,'id'|'createdAt'|'updatedAt'>) {
    const d = await readDb();
    const now = new Date().toISOString();
    const item: Master = { id: crypto.randomUUID(), createdAt: now, updatedAt: now, ...input };
    d.masters.push(item);
    await writeDb(d);
    return item;
  },
  async updateMaster(id: UUID, patch: Partial<Master>) {
    const d = await readDb();
    const idx = d.masters.findIndex(m => m.id === id);
    if (idx === -1) return null;
    d.masters[idx] = { ...d.masters[idx], ...patch, id, updatedAt: new Date().toISOString() };
    await writeDb(d);
    return d.masters[idx];
  },
  async deleteMaster(id: UUID) {
    const d = await readDb();
    const before = d.masters.length;
    d.masters = d.masters.filter(m => m.id !== id);
    await writeDb(d);
    return d.masters.length < before;
  },

  async listGroups() {
    const d = await readDb();
    return d.serviceGroups;
  },
  async addGroup(input: Omit<ServiceGroup,'id'|'createdAt'|'updatedAt'>) {
    const d = await readDb();
    const now = new Date().toISOString();
    const item: ServiceGroup = { id: crypto.randomUUID(), createdAt: now, updatedAt: now, ...input };
    d.serviceGroups.push(item);
    await writeDb(d);
    return item;
  },
  async updateGroup(id: UUID, patch: Partial<ServiceGroup>) {
    const d = await readDb();
    const idx = d.serviceGroups.findIndex(g => g.id === id);
    if (idx === -1) return null;
    d.serviceGroups[idx] = { ...d.serviceGroups[idx], ...patch, id, updatedAt: new Date().toISOString() };
    await writeDb(d);
    return d.serviceGroups[idx];
  },
  async deleteGroup(id: UUID) {
    const d = await readDb();
    d.services = d.services.filter(s => s.groupId !== id);
    d.serviceGroups = d.serviceGroups.filter(g => g.id !== id);
    await writeDb(d);
    return true;
  },

  async listServices() {
    const d = await readDb();
    return d.services;
  },
  async addService(input: Omit<Service,'id'|'createdAt'|'updatedAt'>) {
    const d = await readDb();
    const now = new Date().toISOString();
    const item: Service = { id: crypto.randomUUID(), createdAt: now, updatedAt: now, ...input };
    d.services.push(item);
    await writeDb(d);
    return item;
  },
  async updateService(id: UUID, patch: Partial<Service>) {
    const d = await readDb();
    const idx = d.services.findIndex(s => s.id === id);
    if (idx === -1) return null;
    d.services[idx] = { ...d.services[idx], ...patch, id, updatedAt: new Date().toISOString() };
    await writeDb(d);
    return d.services[idx];
  },
  async deleteService(id: UUID) {
    const d = await readDb();
    d.services = d.services.filter(s => s.id !== id);
    await writeDb(d);
    return true;
  }
};
