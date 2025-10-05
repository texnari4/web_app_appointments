import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
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

type Appointment = {
  id: string;
  masterId: string;
  clientName: string;
  clientPhone: string;
  startsAt: string; // ISO
  endsAt: string;   // ISO
  createdAt: string;
  updatedAt: string;
};

type DBShape = {
  masters: Master[];
  appointments: Appointment[];
};

async function ensureFile() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    const initial: DBShape = { masters: [], appointments: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(initial, null, 2), 'utf-8');
  }
}

async function readDb(): Promise<DBShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf-8');
  try {
    return JSON.parse(raw) as DBShape;
  } catch {
    return { masters: [], appointments: [] };
  }
}

async function writeDb(data: DBShape): Promise<void> {
  await ensureFile();
  await fs.writeFile(DB_FILE, JSON.stringify(data, null, 2), 'utf-8');
}

export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function createMaster(payload: {name: string; phone: string; avatarUrl?: string; isActive?: boolean;}): Promise<Master> {
  const db = await readDb();
  const now = new Date().toISOString();
  const master: Master = {
    id: crypto.randomUUID(),
    name: payload.name,
    phone: payload.phone,
    avatarUrl: payload.avatarUrl || '',
    isActive: payload.isActive ?? true,
    createdAt: now,
    updatedAt: now
  };
  db.masters.push(master);
  await writeDb(db);
  return master;
}

export async function listAppointments(params?: { from?: string; to?: string; masterId?: string }): Promise<Appointment[]> {
  const db = await readDb();
  let items = db.appointments;
  if (params?.masterId) items = items.filter(a => a.masterId === params.masterId);
  if (params?.from) items = items.filter(a => a.startsAt >= params.from!);
  if (params?.to) items = items.filter(a => a.endsAt <= params.to!);
  return items;
}

export async function createAppointment(payload: {
  masterId: string;
  clientName: string;
  clientPhone: string;
  startsAt: string;
  endsAt: string;
}): Promise<Appointment> {
  const db = await readDb();
  const now = new Date().toISOString();
  // Simple overlap check
  const overlap = db.appointments.find(a =>
    a.masterId === payload.masterId &&
    !(payload.endsAt <= a.startsAt || payload.startsAt >= a.endsAt)
  );
  if (overlap) {
    throw new Error('Time slot overlaps existing appointment');
  }
  const appt: Appointment = {
    id: crypto.randomUUID(),
    masterId: payload.masterId,
    clientName: payload.clientName,
    clientPhone: payload.clientPhone,
    startsAt: payload.startsAt,
    endsAt: payload.endsAt,
    createdAt: now,
    updatedAt: now
  };
  db.appointments.push(appt);
  await writeDb(db);
  return appt;
}