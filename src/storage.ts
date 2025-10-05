import { promises as fs } from 'node:fs';
import path from 'node:path';

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

type Master = {
  id: string;
  name: string;
  phone?: string;
  createdAt: string;
};

type DB = {
  masters: Master[];
};

async function ensureDb(): Promise<void> {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    const init: DB = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(init, null, 2), 'utf-8');
  }
}

export async function readDb(): Promise<DB> {
  await ensureDb();
  const raw = await fs.readFile(DB_FILE, 'utf-8');
  try {
    return JSON.parse(raw) as DB;
  } catch {
    const init: DB = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(init, null, 2), 'utf-8');
    return init;
  }
}

export async function writeDb(db: DB): Promise<void> {
  const tmp = DB_FILE + '.tmp';
  await ensureDb();
  await fs.writeFile(tmp, JSON.stringify(db, null, 2), 'utf-8');
  await fs.rename(tmp, DB_FILE);
}
