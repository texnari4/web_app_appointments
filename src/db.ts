import { mkdir, readFile, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const FILES = {
  masters: 'masters.json',
  services: 'services.json',
  appointments: 'appointments.json',
  clients: 'clients.json'
};

type Id = string;

export interface Master {
  id: Id;
  name: string;
  phone?: string;
  avatarUrl?: string;
  isActive?: boolean;
  specialties?: string[];
  description?: string;
  schedule?: {
    type: 'weekly' | 'custom';
    weekly?: { // 0-6: вс-сб
      [weekday: string]: { from: string; to: string }[]; 
    };
    custom?: { date: string; slots: { from: string; to: string }[] }[];
  }
  createdAt: string;
  updatedAt: string;
}

export interface Service {
  id: Id;
  group: string;           // категория (Ногтевой сервис, Волосы, ...)
  title: string;
  description?: string;
  price: number;
  durationMin: number;     // длительность в минутах
  createdAt: string;
  updatedAt: string;
}

export interface Client {
  id: Id;
  name: string;
  phone?: string;
  tg?: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export interface Appointment {
  id: Id;
  masterId: Id;
  serviceId: Id;
  clientId: Id;
  date: string;       // YYYY-MM-DD
  timeFrom: string;   // HH:mm
  timeTo: string;     // HH:mm
  price?: number;     // фиксируется на момент записи
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

async function ensureDataDir() {
  await mkdir(DATA_DIR, { recursive: true });
}

async function filePath(kind: keyof typeof FILES) {
  await ensureDataDir();
  return path.join(DATA_DIR, FILES[kind]);
}

async function readJson<T>(kind: keyof typeof FILES): Promise<T[]> {
  const fp = await filePath(kind);
  try {
    await access(fp);
  } catch {
    await writeFile(fp, '[]', 'utf-8');
  }
  const raw = await readFile(fp, 'utf-8');
  try {
    const arr = JSON.parse(raw);
    if (Array.isArray(arr)) return arr as T[];
    return [];
  } catch {
    return [];
  }
}

async function writeJson<T>(kind: keyof typeof FILES, arr: T[]) {
  const fp = await filePath(kind);
  await writeFile(fp, JSON.stringify(arr, null, 2), 'utf-8');
}

function nowISO() {
  return new Date().toISOString();
}
function newId() {
  return crypto.randomUUID();
}

export const db = {
  async listMasters() { return readJson<Master>('masters'); },
  async upsertMaster(payload: Partial<Master> & { id?: Id }) {
    const list = await readJson<Master>('masters');
    if (payload.id) {
      const idx = list.findIndex(x => x.id === payload.id);
      if (idx >= 0) {
        list[idx] = { ...list[idx], ...payload, updatedAt: nowISO() } as Master;
      } else {
        const now = nowISO();
        list.push({ id: payload.id, name: payload.name || '', isActive: true, createdAt: now, updatedAt: now, ...payload } as Master);
      }
    } else {
      const now = nowISO();
      list.push({ id: newId(), name: payload.name || '', isActive: true, createdAt: now, updatedAt: now, ...payload } as Master);
    }
    await writeJson('masters', list);
    return list[list.length - 1];
  },
  async deleteMaster(id: Id) {
    const list = await readJson<Master>('masters');
    const next = list.filter(x => x.id !== id);
    await writeJson('masters', next);
    return { ok: true };
  },

  async listServices() { return readJson<Service>('services'); },
  async upsertService(payload: Partial<Service> & { id?: Id }) {
    const list = await readJson<Service>('services');
    const now = nowISO();
    if (payload.id) {
      const i = list.findIndex(x => x.id === payload.id);
      if (i >= 0) list[i] = { ...list[i], ...payload, updatedAt: now } as Service;
      else list.push({ id: payload.id, title: payload.title || '', group: payload.group || 'Общее', price: payload.price ?? 0, durationMin: payload.durationMin ?? 60, createdAt: now, updatedAt: now, ...payload } as Service);
    } else {
      list.push({ id: newId(), title: payload.title || '', group: payload.group || 'Общее', price: payload.price ?? 0, durationMin: payload.durationMin ?? 60, createdAt: now, updatedAt: now, ...payload } as Service);
    }
    await writeJson('services', list);
    return list[list.length - 1];
  },
  async deleteService(id: Id) {
    const list = await readJson<Service>('services');
    const next = list.filter(x => x.id !== id);
    await writeJson('services', next);
    return { ok: true };
  },

  async listAppointments() { return readJson<Appointment>('appointments'); },
  async upsertAppointment(payload: Partial<Appointment> & { id?: Id }) {
    const list = await readJson<Appointment>('appointments');
    const now = nowISO();
    if (payload.id) {
      const i = list.findIndex(x => x.id === payload.id);
      if (i >= 0) list[i] = { ...list[i], ...payload, updatedAt: now } as Appointment;
      else list.push({ id: payload.id, createdAt: now, updatedAt: now, ...(payload as any) });
    } else {
      list.push({ id: newId(), createdAt: now, updatedAt: now, ...(payload as any) });
    }
    await writeJson('appointments', list);
    return list[list.length - 1];
  },
  async deleteAppointment(id: Id) {
    const list = await readJson<Appointment>('appointments');
    const next = list.filter(x => x.id !== id);
    await writeJson('appointments', next);
    return { ok: true };
  },

  async listClients() { return readJson<Client>('clients'); },
  async upsertClient(payload: Partial<Client> & { id?: Id }) {
    const list = await readJson<Client>('clients');
    const now = nowISO();
    if (payload.id) {
      const i = list.findIndex(x => x.id === payload.id);
      if (i >= 0) list[i] = { ...list[i], ...payload, updatedAt: now } as Client;
      else list.push({ id: payload.id, name: payload.name || '', createdAt: now, updatedAt: now, ...payload } as Client);
    } else {
      list.push({ id: newId(), name: payload.name || '', createdAt: now, updatedAt: now, ...payload } as Client);
    }
    await writeJson('clients', list);
    return list[list.length - 1];
  },
  async deleteClient(id: Id) {
    const list = await readJson<Client>('clients');
    const next = list.filter(x => x.id !== id);
    await writeJson('clients', next);
    return { ok: true };
  }
};
