import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export interface Master {
  id: string;
  name: string;
  phone: string;
  avatarUrl?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Appointment {
  id: string;
  masterId: string;
  clientName: string;
  clientPhone: string;
  start: string; // ISO
  end: string;   // ISO
  note?: string;
  status: 'scheduled' | 'cancelled' | 'completed';
  createdAt: string;
  updatedAt: string;
}

type DbShape = {
  masters: Master[];
  appointments: Appointment[];
};

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

async function ensureFile() {
  try {
    await fs.mkdir(DATA_DIR, { recursive: true });
    await fs.access(DB_FILE);
  } catch {
    const initial: DbShape = { masters: [], appointments: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2), { mode: 0o664 });
  }
}

export async function readDb(): Promise<DbShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf-8');
  return JSON.parse(raw) as DbShape;
}

async function writeDb(db: DbShape): Promise<void> {
  await fs.writeFile(DB_FILE, JSON.stringify(db, null, 2));
}

// --- Masters ---
export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function addMaster(input: Omit<Master, 'id' | 'createdAt' | 'updatedAt'>): Promise<Master> {
  const db = await readDb();
  const now = new Date().toISOString();
  const master: Master = {
    id: crypto.randomUUID(),
    createdAt: now,
    updatedAt: now,
    ...input
  };
  db.masters.push(master);
  await writeDb(db);
  return master;
}

// --- Appointments ---
export async function listAppointments(params: { masterId?: string; from?: string; to?: string } = {}): Promise<Appointment[]> {
  const db = await readDb();
  return db.appointments.filter(a => {
    if (params.masterId && a.masterId !== params.masterId) return false;
    if (params.from && a.end <= params.from) return false;
    if (params.to && a.start >= params.to) return false;
    return true;
  }).sort((a,b)=> a.start.localeCompare(b.start));
}

export async function addAppointment(input: Omit<Appointment, 'id' | 'createdAt' | 'updatedAt'>): Promise<Appointment> {
  const db = await readDb();
  // conflict check
  const overlap = db.appointments.find(a => a.masterId === input.masterId && !(a.end <= input.start || a.start >= input.end));
  if (overlap) {
    throw new Error('TIME_CONFLICT');
  }
  const now = new Date().toISOString();
  const appt: Appointment = { id: crypto.randomUUID(), createdAt: now, updatedAt: now, ...input };
  db.appointments.push(appt);
  await writeDb(db);
  return appt;
}