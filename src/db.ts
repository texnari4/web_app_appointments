import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

const DATA_DIR = process.env.DATA_DIR ?? '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

type Master = {
  id: string;
  name: string;
  phone: string;
  avatarUrl: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

type Appointment = {
  id: string;
  masterId: string;
  clientName: string;
  phone: string;
  from: string; // ISO
  to: string;   // ISO
  note?: string;
  createdAt: string;
  updatedAt: string;
};

type DB = {
  masters: Master[];
  appointments: Appointment[];
};

async function ensureFile() {
  await mkdir(DATA_DIR, { recursive: True });
  try {
    await readFile(DB_FILE, 'utf8');
  } catch {
    const empty: DB = { masters: [], appointments: [] };
    await writeFile(DB_FILE, JSON.stringify(empty, null, 2), 'utf8');
  }
}

export async function ensureReady() {
  await ensureFile();
}

async function readDb(): Promise<DB> {
  await ensureFile();
  const raw = await readFile(DB_FILE, 'utf8');
  return JSON.parse(raw) as DB;
}

async function writeDb(db: DB): Promise<void> {
  await writeFile(DB_FILE, JSON.stringify(db, null, 2), 'utf8');
}

function uuid() {
  return crypto.randomUUID();
}

export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function createMaster(params: { name: string; phone: string; avatarUrl: string; isActive: boolean; }): Promise<Master> {
  const now = new Date().toISOString();
  const item: Master = { id: uuid(), createdAt: now, updatedAt: now, ...params };
  const db = await readDb();
  db.masters.push(item);
  await writeDb(db);
  return item;
}

export async function listAppointments(): Promise<Appointment[]> {
  const db = await readDb();
  return db.appointments;
}

export async function createAppointment(params: { masterId: string; clientName: string; phone: string; from: string; to: string; note?: string; }): Promise<Appointment> {
  const db = await readDb();
  // time conflict check
  const from = new Date(params.from).getTime();
  const to = new Date(params.to).getTime();
  for (const a of db.appointments.filter(x => x.masterId === params.masterId)) {
    const af = new Date(a.from).getTime();
    const at = new Date(a.to).getTime();
    const overlap = Math.max(af, from) < Math.min(at, to);
    if (overlap) {
      const err = new Error('TIME_CONFLICT');
      throw err;
    }
  }
  const now = new Date().toISOString();
  const item: Appointment = { id: uuid(), createdAt: now, updatedAt: now, ...params };
  db.appointments.push(item);
  await writeDb(db);
  return item;
}
