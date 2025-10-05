import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const DATA_DIR = process.env.DATA_DIR || '/data';
const DB_PATH = path.join(DATA_DIR, 'db.json');

type Master = {
  id: string;
  name: string;
  phone?: string;
  avatarUrl?: string;
  isActive?: boolean;
  createdAt: string;
  updatedAt: string;
};

type DbShape = {
  masters: Master[];
};

async function ensureDir() {
  try {
    await fs.mkdir(DATA_DIR, { recursive: true });
  } catch (_) {
    // ignore (mounted volume may restrict perms to change ownership)
  }
}

export async function ensureDb() {
  await ensureDir();
  try {
    await fs.access(DB_PATH);
  } catch {
    const seed: DbShape = { masters: [] };
    await fs.writeFile(DB_PATH, JSON.stringify(seed, null, 2), 'utf8');
  }
}

async function readDb(): Promise<DbShape> {
  await ensureDb();
  const raw = await fs.readFile(DB_PATH, 'utf8');
  return JSON.parse(raw || '{"masters":[]}');
}

async function writeDb(db: DbShape) {
  await fs.writeFile(DB_PATH, JSON.stringify(db, null, 2), 'utf8');
}

export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function createMaster(payload: Partial<Master>): Promise<Master> {
  const now = new Date().toISOString();
  const m: Master = {
    id: crypto.randomUUID(),
    name: payload.name || 'Без имени',
    phone: payload.phone || '',
    avatarUrl: payload.avatarUrl || '',
    isActive: payload.isActive ?? true,
    createdAt: now,
    updatedAt: now
  };
  const db = await readDb();
  db.masters.push(m);
  await writeDb(db);
  return m;
}