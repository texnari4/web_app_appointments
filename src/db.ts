
import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

type Master = {
  id: string;
  name: string;
  phone: string;
  avatarUrl?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

type Database = {
  masters: Master[];
};

async function ensureFile() {
  await fs.mkdir(path.dirname(DB_FILE), { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    const initial: Database = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2), 'utf-8');
  }
}

async function readDb(): Promise<Database> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf-8');
  return JSON.parse(raw || '{"masters":[]}');
}

async function writeDb(db: Database) {
  await ensureFile();
  const tmp = DB_FILE + '.tmp';
  await fs.writeFile(tmp, JSON.stringify(db, null, 2), 'utf-8');
  await fs.rename(tmp, DB_FILE);
}

export async function listMasters() {
  const db = await readDb();
  return db.masters;
}

export async function addMaster(data: Omit<Master, 'id' | 'createdAt' | 'updatedAt' | 'isActive'> & Partial<Pick<Master,'isActive'>>) {
  const db = await readDb();
  const now = new Date().toISOString();
  const item: Master = {
    id: crypto.randomUUID(),
    name: data.name,
    phone: data.phone,
    avatarUrl: data.avatarUrl,
    isActive: data.isActive ?? true, // <-- will be fixed below to 'true'
    createdAt: now,
    updatedAt: now
  };
  db.masters.push(item);
  await writeDb(db);
  return item;
}

export async function deleteMaster(id: string) {
  const db = await readDb();
  const before = db.masters.length;
  db.masters = db.masters.filter(m => m.id !== id);
  if (db.masters.length !== before) {
    await writeDb(db);
    return true;
  }
  return false;
}
