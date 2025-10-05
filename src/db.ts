
import { promises as fs } from 'fs';
import path from 'path';

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = process.env.DB_FILE || path.join(DATA_DIR, 'db.json');

type Master = {
  id: string;
  name: string;
  phone?: string;
  avatarUrl?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

type DbShape = {
  version: string;
  masters: Master[];
};

async function ensureFile(): Promise<void> {
  try {
    await fs.mkdir(DATA_DIR, { recursive: true });
  } catch {}
  try {
    await fs.access(DB_FILE);
  } catch {
    const initial: DbShape = { version: '1', masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2), 'utf8');
  }
}

async function readDb(): Promise<DbShape> {
  await ensureFile();
  const buf = await fs.readFile(DB_FILE, 'utf8');
  return JSON.parse(buf) as DbShape;
}

async function writeDb(db: DbShape): Promise<void> {
  await ensureFile();
  await fs.writeFile(DB_FILE, JSON.stringify(db, null, 2), 'utf8');
}

export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function createMaster(m: Omit<Master, 'id' | 'createdAt' | 'updatedAt'> & { id: string }): Promise<Master> {
  const db = await readDb();
  const now = new Date().toISOString();
  const full: Master = { ...m, createdAt: now, updatedAt: now };
  db.masters.push(full);
  await writeDb(db);
  return full;
}

export async function updateMaster(id: string, patch: Partial<Omit<Master, 'id' | 'createdAt'>>): Promise<Master | null> {
  const db = await readDb();
  const idx = db.masters.findIndex(x => x.id === id);
  if (idx === -1) return null;
  db.masters[idx] = { ...db.masters[idx], ...patch, updatedAt: new Date().toISOString() };
  await writeDb(db);
  return db.masters[idx];
}

export async function deleteMaster(id: string): Promise<boolean> {
  const db = await readDb();
  const before = db.masters.length;
  db.masters = db.masters.filter(x => x.id !== id);
  await writeDb(db);
  return db.masters.length < before;
}
