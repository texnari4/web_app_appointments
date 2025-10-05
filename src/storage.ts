import { promises as fs } from 'fs';
import path from 'path';

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_PATH = path.join(DATA_DIR, 'db.json');

type Master = {
  id: string;
  name: string;
  phone?: string;
  about?: string;
  createdAt: string;
};

type DB = {
  version?: string;
  masters: Master[];
};

async function readDB(): Promise<DB> {
  try {
    const buf = await fs.readFile(DB_PATH, 'utf-8');
    return JSON.parse(buf) as DB;
  } catch (e: any) {
    if (e.code === 'ENOENT') {
      const fresh: DB = { version: '2.4.4', masters: [] };
      await writeDB(fresh);
      return fresh;
    }
    throw e;
  }
}

async function writeDB(db: DB): Promise<void> {
  const tmp = DB_PATH + '.tmp';
  await fs.writeFile(tmp, JSON.stringify(db, null, 2), 'utf-8');
  await fs.rename(tmp, DB_PATH);
}

export async function listMasters(): Promise<Master[]> {
  const db = await readDB();
  return db.masters;
}

export async function addMaster(m: Omit<Master, 'id'|'createdAt'>): Promise<Master> {
  const db = await readDB();
  const master: Master = {
    id: crypto.randomUUID(),
    createdAt: new Date().toISOString(),
    ...m
  };
  db.masters.push(master);
  await writeDB(db);
  return master;
}

export async function removeMaster(id: string): Promise<boolean> {
  const db = await readDB();
  const before = db.masters.length;
  db.masters = db.masters.filter(m => m.id !== id);
  const changed = db.masters.length !== before;
  if (changed) await writeDB(db);
  return changed;
}
