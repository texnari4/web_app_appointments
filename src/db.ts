import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

export type Master = {
  id: string;
  name: string;
  phone: string;
  avatarUrl?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

export type DbShape = {
  masters: Master[];
};

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_PATH = path.join(DATA_DIR, 'db.json');

async function ensureFile() {
  try {
    await access(DATA_DIR);
  } catch {
    await mkdir(DATA_DIR, { recursive: true });
  }
  try {
    await access(DB_PATH);
  } catch {
    const initial: DbShape = { masters: [] };
    await writeFile(DB_PATH, JSON.stringify(initial, null, 2), 'utf8');
  }
}

async function readDb(): Promise<DbShape> {
  await ensureFile();
  const raw = await readFile(DB_PATH, 'utf8');
  return JSON.parse(raw || '{"masters":[]}');
}

async function writeDb(db: DbShape): Promise<void> {
  await writeFile(DB_PATH, JSON.stringify(db, null, 2), 'utf8');
}

export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  // newest first
  return [...db.masters].sort((a,b) => b.createdAt.localeCompare(a.createdAt));
}

export async function addMaster(data: Pick<Master,'name'|'phone'|'avatarUrl'|'isActive'>): Promise<Master> {
  const now = new Date().toISOString();
  const master: Master = {
    id: crypto.randomUUID(),
    name: data.name,
    phone: data.phone,
    avatarUrl: data.avatarUrl,
    isActive: data.isActive ?? true,
    createdAt: now,
    updatedAt: now,
  };
  const db = await readDb();
  db.masters.push(master);
  await writeDb(db);
  return master;
}

export async function setMasterActive(id: string, value: boolean): Promise<Master | null> {
  const db = await readDb();
  const idx = db.masters.findIndex(m => m.id === id);
  if (idx === -1) return null;
  db.masters[idx].isActive = value;
  db.masters[idx].updatedAt = new Date().toISOString();
  await writeDb(db);
  return db.masters[idx];
}