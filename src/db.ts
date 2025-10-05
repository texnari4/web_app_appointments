import fs from 'node:fs/promises';
import path from 'node:path';

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

type Master = {
  id: string;
  name: string;
  phone?: string;
  avatarUrl?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

type DbShape = {
  masters: Master[];
};

async function ensureFile() {
  try {
    await fs.mkdir(DATA_DIR, { recursive: true });
    // Try open existing; if not exists, create minimal JSON
    try {
      await fs.access(DB_FILE);
    } catch {
      const initial: DbShape = { masters: [] };
      await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2));
    }
    // Relax permissions for Railway volume edge-cases
    try {
      await fs.chmod(DATA_DIR, 0o777);
      await fs.chmod(DB_FILE, 0o666);
    } catch {}
  } catch (e) {
    throw e;
  }
}

export async function ensureDataWritable() {
  await ensureFile();
}

async function readDb(): Promise<DbShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf8');
  try {
    return JSON.parse(raw) as DbShape;
  } catch {
    // If corrupted, reset safely
    const empty: DbShape = { masters: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(empty, null, 2));
    return empty;
  }
}

async function writeDb(db: DbShape) {
  await fs.writeFile(DB_FILE, JSON.stringify(db, null, 2));
  try {
    await fs.chmod(DB_FILE, 0o666);
  } catch {}
}

export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function createMaster(input: Partial<Master>): Promise<Master> {
  const db = await readDb();
  const now = new Date().toISOString();
  const id = crypto.randomUUID();
  const name = (input.name || '').toString().trim();
  if (!name) throw new Error('name is required');
  const m: Master = {
    id,
    name,
    phone: (input.phone || '').toString(),
    avatarUrl: (input.avatarUrl || '').toString(),
    isActive: input.isActive !== false,
    createdAt: now,
    updatedAt: now
  };
  db.masters.push(m);
  await writeDb(db);
  return m;
}

export async function updateMaster(id: string, input: Partial<Master>): Promise<Master | null> {
  const db = await readDb();
  const idx = db.masters.findIndex(m => m.id === id);
  if (idx === -1) return null;
  const prev = db.masters[idx];
  const next: Master = {
    ...prev,
    name: input.name !== undefined ? String(input.name) : prev.name,
    phone: input.phone !== undefined ? String(input.phone) : prev.phone,
    avatarUrl: input.avatarUrl !== undefined ? String(input.avatarUrl) : prev.avatarUrl,
    isActive: input.isActive !== undefined ? Boolean(input.isActive) : prev.isActive,
    updatedAt: new Date().toISOString(),
  };
  db.masters[idx] = next;
  await writeDb(db);
  return next;
}

export async function deleteMaster(id: string): Promise<boolean> {
  const db = await readDb();
  const before = db.masters.length;
  db.masters = db.masters.filter(m => m.id != id);
  if (db.masters.length === before) return false;
  await writeDb(db);
  return true;
}
