// File-based storage for Services (safe, self-contained)
import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import type { ServicesDbShape, ServiceGroup, ServiceItem } from './types';

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const FILE_PATH = path.join(DATA_DIR, 'services.json');

async function ensureFile(): Promise<void> {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(FILE_PATH);
  } catch {
    const now = new Date().toISOString();
    const seed: ServicesDbShape = { groups: [], items: [] };
    await fs.writeFile(FILE_PATH, JSON.stringify(seed, null, 2), 'utf-8');
  }
}

async function readDb(): Promise<ServicesDbShape> {
  await ensureFile();
  const raw = await fs.readFile(FILE_PATH, 'utf-8');
  try { return JSON.parse(raw) as ServicesDbShape; }
  catch {
    // If corrupted, back it up and reset
    const backup = FILE_PATH + '.bak-' + Date.now();
    await fs.writeFile(backup, raw, 'utf-8').catch(() => {});
    const empty: ServicesDbShape = { groups: [], items: [] };
    await fs.writeFile(FILE_PATH, JSON.stringify(empty, null, 2), 'utf-8');
    return empty;
  }
}

async function writeDb(db: ServicesDbShape): Promise<void> {
  await fs.writeFile(FILE_PATH, JSON.stringify(db, null, 2), 'utf-8');
}

function uid(): string {
  return crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex');
}

// --- Public API ---
export async function listAll() {
  const db = await readDb();
  return db;
}

// Groups
export async function createGroup(input: { name: string; isActive?: boolean }): Promise<ServiceGroup> {
  const db = await readDb();
  const now = new Date().toISOString();
  const g: ServiceGroup = {
    id: uid(),
    name: (input.name || '').trim(),
    isActive: input.isActive ?? true,
    createdAt: now,
    updatedAt: now,
  };
  db.groups.push(g);
  await writeDb(db);
  return g;
}

export async function updateGroup(id: string, patch: Partial<Omit<ServiceGroup, 'id'|'createdAt'>>): Promise<ServiceGroup> {
  const db = await readDb();
  const idx = db.groups.findIndex(x => x.id === id);
  if (idx === -1) throw new Error('Group not found');
  const now = new Date().toISOString();
  db.groups[idx] = { ...db.groups[idx], ...patch, id, updatedAt: now };
  await writeDb(db);
  return db.groups[idx];
}

export async function deleteGroup(id: string): Promise<void> {
  const db = await readDb();
  db.items = db.items.filter(s => s.groupId !== id);
  db.groups = db.groups.filter(g => g.id !== id);
  await writeDb(db);
}

// Items
export async function createService(input: {
  groupId: string;
  name: string;
  description?: string;
  price: number;
  durationMinutes: number;
  isActive?: boolean;
}): Promise<ServiceItem> {
  const db = await readDb();
  if (!db.groups.some(g => g.id === input.groupId)) throw new Error('groupId not found');
  const now = new Date().toISOString();
  const item: ServiceItem = {
    id: uid(),
    groupId: input.groupId,
    name: (input.name || '').trim(),
    description: input.description?.trim() || '',
    price: Number(input.price),
    durationMinutes: Math.max(0, Math.floor(Number(input.durationMinutes))),
    isActive: input.isActive ?? true,
    createdAt: now,
    updatedAt: now,
  };
  db.items.push(item);
  await writeDb(db);
  return item;
}

export async function updateService(id: string, patch: Partial<Omit<ServiceItem,'id'|'createdAt'>>): Promise<ServiceItem> {
  const db = await readDb();
  const idx = db.items.findIndex(x => x.id === id);
  if (idx === -1) throw new Error('Service not found');
  if (patch.groupId && !db.groups.some(g => g.id === patch.groupId)) throw new Error('groupId not found');
  const now = new Date().toISOString();
  db.items[idx] = { ...db.items[idx], ...patch, id, updatedAt: now };
  await writeDb(db);
  return db.items[idx];
}

export async function deleteService(id: string): Promise<void> {
  const db = await readDb();
  db.items = db.items.filter(s => s.id !== id);
  await writeDb(db);
}
