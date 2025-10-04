import { promises as fs } from 'node:fs';
import path from 'node:path';

export type Master = {
  id: string;
  name: string;
  phone?: string;
  about?: string;
  avatarUrl?: string;
  createdAt: string;
  updatedAt: string;
};

export type Service = {
  id: string;
  title: string;
  price?: number;
  durationMin?: number;
  createdAt: string;
  updatedAt: string;
};

type DB = {
  meta: { version: string; createdAt: string };
  masters: Master[];
  services: Service[];
};

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');
const TMP_FILE = path.join(DATA_DIR, 'db.json.tmp');

async function readJSON<T>(file: string): Promise<T> {
  const buf = await fs.readFile(file);
  return JSON.parse(buf.toString('utf-8')) as T;
}

async function writeJSON<T>(file: string, data: T): Promise<void> {
  const txt = JSON.stringify(data, null, 2);
  await fs.writeFile(TMP_FILE, txt);
  await fs.rename(TMP_FILE, file);
}

export async function loadDB(): Promise<DB> {
  try {
    return await readJSON<DB>(DB_FILE);
  } catch {
    const fresh: DB = { meta: { version: '2.4.0', createdAt: new Date().toISOString() }, masters: [], services: [] };
    await writeJSON(DB_FILE, fresh);
    return fresh;
  }
}

export async function saveDB(db: DB): Promise<void> {
  await writeJSON(DB_FILE, db);
}

function uid(): string {
  return Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
}

// Masters
export async function listMasters(): Promise<Master[]> {
  const db = await loadDB();
  return db.masters;
}

export async function createMaster(input: Partial<Master> & { name: string }): Promise<Master> {
  const now = new Date().toISOString();
  const m: Master = {
    id: uid(),
    name: input.name,
    phone: input.phone,
    about: input.about,
    avatarUrl: input.avatarUrl,
    createdAt: now,
    updatedAt: now,
  };
  const db = await loadDB();
  db.masters.push(m);
  await saveDB(db);
  return m;
}

export async function deleteMaster(id: string): Promise<boolean> {
  const db = await loadDB();
  const before = db.masters.length;
  db.masters = db.masters.filter(m => m.id !== id);
  const changed = db.masters.length !== before;
  if (changed) await saveDB(db);
  return changed;
}
