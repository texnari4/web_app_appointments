
import { promises as fs } from 'node:fs';
import path from 'node:path';

export type Master = {
  id: string;
  name: string;
  phone?: string;
  avatarUrl?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = process.env.DB_FILE || path.join(DATA_DIR, 'db.json');

type DbShape = {
  masters: Master[];
};

async function ensureFile() {
  await fs.mkdir(path.dirname(DB_FILE), { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    const initial: DbShape = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2), 'utf8');
  }
}

async function readDb(): Promise<DbShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf8');
  try {
    return JSON.parse(raw || '{"masters":[]}');
  } catch {
    // если файл поврежден — переинициализируем
    const initial: DbShape = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2), 'utf8');
    return initial;
  }
}

async function writeDb(db: DbShape): Promise<void> {
  await ensureFile();
  await fs.writeFile(DB_FILE, JSON.stringify(db, null, 2), 'utf8');
}

export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function createMaster(m: Omit<Master, 'id'|'createdAt'|'updatedAt'> & { id: string }): Promise<Master> {
  const db = await readDb();
  const now = new Date().toISOString();
  const record: Master = { ...m, createdAt: now, updatedAt: now };
  db.masters.push(record);
  await writeDb(db);
  return record;
}

export async function updateMaster(id: string, patch: Partial<Omit<Master, 'id'|'createdAt'>>): Promise<Master | null> {
  const db = await readDb();
  const idx = db.masters.findIndex(x => x.id === id);
  if (idx === -1) return null;
  const merged = { ...db.masters[idx], ...patch, updatedAt: new Date().toISOString() };
  db.masters[idx] = merged;
  await writeDb(db);
  return merged;
}

export async function deleteMaster(id: string): Promise<boolean> {
  const db = await readDb();
  const before = db.masters.length;
  db.masters = db.masters.filter(x => x.id !== id);
  await writeDb(db);
  return db.masters.length !== before;
}
