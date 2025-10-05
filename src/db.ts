
import { promises as fs } from 'fs';
import path from 'path';

export type Master = {
  id: string;
  name: string;
  phone?: string;
  about?: string;
  createdAt: string;
};

type DbShape = {
  masters: Master[];
};

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

async function ensureFile() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    const seed: DbShape = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(seed, null, 2), 'utf-8');
  }
}

export async function readDb(): Promise<DbShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf-8');
  try {
    return JSON.parse(raw) as DbShape;
  } catch {
    // if corrupted, reset file
    const seed: DbShape = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(seed, null, 2), 'utf-8');
    return seed;
  }
}

export async function writeDb(data: DbShape): Promise<void> {
  await ensureFile();
  await fs.writeFile(DB_FILE, JSON.stringify(data, null, 2), 'utf-8');
}

// CRUD
export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function createMaster(input: Omit<Master, 'id' | 'createdAt'>): Promise<Master> {
  const db = await readDb();
  const master: Master = {
    id: crypto.randomUUID(),
    createdAt: new Date().toISOString(),
    ...input,
  };
  db.masters.push(master);
  await writeDb(db);
  return master;
}

export async function updateMaster(id: string, patch: Partial<Omit<Master, 'id' | 'createdAt'>>): Promise<Master | null> {
  const db = await readDb();
  const idx = db.masters.findIndex(m => m.id === id);
  if (idx === -1) return null;
  db.masters[idx] = { ...db.masters[idx], ...patch };
  await writeDb(db);
  return db.masters[idx];
}

export async function deleteMaster(id: string): Promise<boolean> {
  const db = await readDb();
  const before = db.masters.length;
  db.masters = db.masters.filter(m => m.id != id);
  await writeDb(db);
  return db.masters.length !== before;
}
