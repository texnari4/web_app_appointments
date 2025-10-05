
import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { Appointment, DbShape, Master } from "./types.js";

const DATA_DIR = process.env.DATA_DIR || path.resolve(process.cwd(), "data");
const DB_FILE = path.join(DATA_DIR, "db.json");

async function ensureDir() {
  await fs.mkdir(DATA_DIR, { recursive: true });
}

async function ensureFile() {
  await ensureDir();
  try {
    await fs.access(DB_FILE);
  } catch {
    const empty: DbShape = { masters: [], appointments: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(empty, null, 2), { mode: 0o664 });
  }
}

export async function readDb(): Promise<DbShape> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, "utf-8");
  try {
    return JSON.parse(raw);
  } catch {
    const fallback: DbShape = { masters: [], appointments: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(fallback, null, 2));
    return fallback;
  }
}

export async function writeDb(db: DbShape): Promise<void> {
  await ensureFile();
  await fs.writeFile(DB_FILE, JSON.stringify(db, null, 2));
}

/** Masters **/
export async function listMasters(): Promise<Master[]> {
  const db = await readDb();
  return db.masters;
}

export async function addMaster(input: Omit<Master, "id" | "createdAt" | "updatedAt">): Promise<Master> {
  const db = await readDb();
  const now = new Date().toISOString();
  const obj: Master = { id: randomUUID(), createdAt: now, updatedAt: now, ...input };
  db.masters.push(obj);
  await writeDb(db);
  return obj;
}

/** Appointments **/
export async function listAppointments(params?: { masterId?: string; from?: string; to?: string }): Promise<Appointment[]> {
  const db = await readDb();
  let items = db.appointments;
  if (params?.masterId) items = items.filter(a => a.masterId === params.masterId);
  if (params?.from) items = items.filter(a => a.end > params.from);
  if (params?.to) items = items.filter(a => a.start < params.to);
  return items.sort((a,b)=>a.start.localeCompare(b.start));
}

export function overlaps(aStart: string, aEnd: string, bStart: string, bEnd: string): boolean {
  return aStart < bEnd && bStart < aEnd;
}

export async function createAppointment(input: Omit<Appointment, "id" | "createdAt" | "updatedAt" | "status"> & { status?: Appointment["status"] }): Promise<Appointment> {
  const db = await readDb();
  // basic referential check
  const master = db.masters.find(m => m.id === input.masterId && m.isActive);
  if (!master) throw new Error("MASTER_NOT_FOUND_OR_INACTIVE");

  // conflict check
  const conflict = db.appointments.find(a =>
    a.masterId === input.masterId &&
    a.status === "scheduled" &&
    overlaps(a.start, a.end, input.start, input.end)
  );
  if (conflict) throw new Error("TIME_CONFLICT");

  const now = new Date().toISOString();
  const obj: Appointment = {
    id: randomUUID(),
    status: input.status ?? "scheduled",
    createdAt: now,
    updatedAt: now,
    ...input
  };
  db.appointments.push(obj);
  await writeDb(db);
  return obj;
}

export async function updateAppointment(id: string, patch: Partial<Appointment>): Promise<Appointment> {
  const db = await readDb();
  const idx = db.appointments.findIndex(a => a.id === id);
  if (idx === -1) throw new Error("NOT_FOUND");
  const now = new Date().toISOString();
  const updated = { ...db.appointments[idx], ...patch, updatedAt: now };
  db.appointments[idx] = updated;
  await writeDb(db);
  return updated;
}

export async function removeAppointment(id: string): Promise<void> {
  const db = await readDb();
  db.appointments = db.appointments.filter(a => a.id !== id);
  await writeDb(db);
}
