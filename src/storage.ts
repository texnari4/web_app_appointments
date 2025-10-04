
import { promises as fs } from 'fs';
import { join } from 'path';

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = join(DATA_DIR, 'db.json');

export type Master = { id: string; name: string; phone?: string|null; about?: string|null; avatarUrl?: string|null };
type Db = { masters: Master[] };

async function readDb(): Promise<Db> {
  try {
    const raw = await fs.readFile(DB_FILE, 'utf-8');
    return JSON.parse(raw);
  } catch {
    return { masters: [] };
  }
}

async function writeDb(db: Db) {
  const tmp = DB_FILE + '.tmp';
  await fs.writeFile(tmp, JSON.stringify(db, null, 2));
  await fs.rename(tmp, DB_FILE);
}

function uid() { return Math.random().toString(36).slice(2, 10); }

export const storage = {
  masters: {
    async all() {
      const db = await readDb();
      return db.masters;
    },
    async create(input: Omit<Master, 'id'>) {
      const db = await readDb();
      const item: Master = { id: uid(), ...input };
      db.masters.push(item);
      await writeDb(db);
      return item;
    },
    async remove(id: string) {
      const db = await readDb();
      const before = db.masters.length;
      db.masters = db.masters.filter(m => m.id !== id);
      if (db.masters.length !== before) await writeDb(db);
      return before !== db.masters.length;
    }
  }
};
