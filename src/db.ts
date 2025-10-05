import { promises as fs } from 'node:fs';
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
  specialties?: string[];
  description?: string;
  schedule?: {
    daysOfWeek?: number[];
    slots?: string[];
  };
};

export type Service = {
  id: string;
  name: string;
  description?: string;
  price: number;
  durationMin: number;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

export type Client = {
  id: string;
  name: string;
  phone?: string;
  tg?: string;
  createdAt: string;
  updatedAt: string;
};

export type Booking = {
  id: string;
  masterId: string;
  serviceId: string;
  clientId: string;
  start: string;
  end: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
};

type DBShape = {
  masters: Master[];
  services: Service[];
  clients: Client[];
  bookings: Booking[];
};

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

async function ensureFile() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    const initial: DBShape = { masters: [], services: [], clients: [], bookings: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2), 'utf8');
  }
}

async function readDb(): Promise<DBShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf8');
  return JSON.parse(raw) as DBShape;
}

async function atomicWrite(obj: DBShape) {
  const tmp = DB_FILE + '.tmp';
  await fs.writeFile(tmp, JSON.stringify(obj, null, 2), 'utf8');
  await fs.rename(tmp, DB_FILE);
}

function uid() {
  return crypto.randomUUID();
}

// Masters
export async function listMasters() {
  const db = await readDb();
  return db.masters;
}

export async function createMaster(input: Omit<Master, 'id'|'createdAt'|'updatedAt'|'isActive'> & { isActive?: boolean }) {
  const now = new Date().toISOString();
  const master: Master = {
    id: uid(),
    name: input.name,
    phone: input.phone,
    avatarUrl: input.avatarUrl,
    specialties: input.specialties ?? [],
    description: input.description,
    schedule: input.schedule,
    isActive: input.isActive ?? true, // placeholder to demonstrate the previous error
    createdAt: now,
    updatedAt: now
  };
  const db = await readDb();
  db.masters.push(master);
  await atomicWrite(db);
  return master;
}

export async function replaceMasters(all: Master[]) {
  const db = await readDb();
  db.masters = all;
  await atomicWrite(db);
}
