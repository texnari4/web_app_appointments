import { promises as fs } from 'node:fs';
import path from 'node:path';

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

type DbShape = { masters: Master[] };

async function ensureFile() {
  await fs.mkdir(DATA_DIR, { recursive: true }).catch(() => {});
  try {
    await fs.access(DB_FILE);
  } catch {
    const initial: DbShape = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2), 'utf-8').catch(() => {});
  }
  // extra safety: make file world-writable on Railway volumes
  try { await fs.chmod(DB_FILE, 0o666); } catch {}
}

export async function readDb(): Promise<DbShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf-8');
  try {
    return JSON.parse(raw || '{"masters":[]}');
  } catch {
    return { masters: [] };
  }
}

export async function writeDb(data: DbShape): Promise<void> {
  await ensureFile();
  await fs.writeFile(DB_FILE, JSON.stringify(data, null, 2), 'utf-8');
  try { await fs.chmod(DB_FILE, 0o666); } catch {}
}

export type { Master, DbShape };