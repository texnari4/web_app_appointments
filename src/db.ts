import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const DATA_DIR = process.env.DATA_DIR || '/app/data';
const DB_FILE = path.join(DATA_DIR, 'db.json');

type ID = string;
export interface Master {
  id: ID;
  name: string;
  phone?: string;
  avatarUrl?: string;
  isActive: boolean;
  specialties?: string[];
  description?: string;
  schedule?: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
}
export interface Service {
  id: ID;
  name: string;
  description?: string;
  price?: number;
  durationMin?: number;
  createdAt: string;
  updatedAt: string;
}
export interface Client {
  id: ID;
  name: string;
  phone?: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}
export interface Appointment {
  id: ID;
  masterId: ID;
  clientId: ID;
  serviceId: ID;
  start: string; // ISO
  end: string;   // ISO
  createdAt: string;
  updatedAt: string;
}

export interface DB {
  masters: Master[];
  services: Service[];
  clients: Client[];
  appointments: Appointment[];
}

async function ensureFile(){
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    const empty: DB = { masters: [], services: [], clients: [], appointments: [] };
    await fs.writeFile(DB_FILE, JSON.stringify(empty, null, 2), 'utf-8');
  }
}

async function readDb(): Promise<DB> {
  await ensureFile();
  const raw = await fs.readFile(DB_FILE, 'utf-8');
  return JSON.parse(raw) as DB;
}

async function writeDb(db: DB): Promise<void> {
  const tmp = DB_FILE + '.tmp';
  await fs.writeFile(tmp, JSON.stringify(db, null, 2), 'utf-8');
  await fs.rename(tmp, DB_FILE);
}

const now = () => new Date().toISOString();
const uid = () => crypto.randomUUID();

// Masters
export async function listMasters(){ const db = await readDb(); return db.masters; }
export async function createMaster(data: Partial<Master>){
  const db = await readDb();
  const item: Master = {
    id: uid(),
    name: data.name || '',
    phone: data.phone || '',
    avatarUrl: data.avatarUrl || '',
    isActive: data.isActive ?? true,
    specialties: data.specialties || [],
    description: data.description || '',
    schedule: data.schedule || {},
    createdAt: now(),
    updatedAt: now()
  };
  db.masters.unshift(item);
  await writeDb(db);
  return item;
}
export async function updateMaster(id: ID, patch: Partial<Master>){
  const db = await readDb();
  const i = db.masters.findIndex(m => m.id === id);
  if(i === -1) return null;
  db.masters[i] = { ...db.masters[i], ...patch, updatedAt: now() };
  await writeDb(db);
  return db.masters[i];
}
export async function deleteMaster(id: ID){
  const db = await readDb();
  db.masters = db.masters.filter(m => m.id !== id);
  await writeDb(db);
  return true;
}
