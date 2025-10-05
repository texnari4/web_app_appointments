import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export type Master = {
  id: string;
  name: string;
  phone?: string;
  avatarUrl?: string;
  isActive: boolean;
  specialties?: string[];
  description?: string;
  schedule?: {
    type: 'weekly' | 'custom';
    weekly?: { [weekday: string]: { from: string; to: string }[] }; // e.g. Mon..Sun
    custom?: { date: string; from: string; to: string }[];
  }
  createdAt: string;
  updatedAt: string;
};

export type ServiceGroup = {
  id: string;
  name: string; // e.g., Ногтевой сервис
  description?: string;
  sort?: number;
  services: Service[];
}

export type Service = {
  id: string;
  groupId: string;
  name: string;
  description?: string;
  price: number;
  durationMinutes: number;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

export type Client = {
  id: string;
  name: string;
  phone?: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
};

export type Booking = {
  id: string;
  masterId: string;
  clientId: string;
  serviceId: string;
  date: string; // ISO date
  start: string; // HH:mm
  end: string;   // HH:mm
  comment?: string;
  createdAt: string;
  updatedAt: string;
};

export type DbShape = {
  masters: Master[];
  serviceGroups: ServiceGroup[];
  clients: Client[];
  bookings: Booking[];
};

const DATA_DIR = process.env.DATA_DIR || '/data';
const DB_PATH = path.join(DATA_DIR, 'db.json');

async function ensureDbFile(): Promise<void> {
  try {
    await fs.mkdir(DATA_DIR, { recursive: true });
    await fs.access(DB_PATH);
  } catch {
    // Seed default dataset
    const now = new Date().toISOString();
    const masterId = crypto.randomUUID();
    const groupId = crypto.randomUUID();
    const serviceId = crypto.randomUUID();

    const seed: DbShape = {
      masters: [
        {
          id: masterId,
          name: 'Юлия',
          phone: '+375331126113',
          avatarUrl: 'https://placehold.co/96x96',
          isActive: true,
          specialties: ['Маникюр', 'Педикюр'],
          description: 'Опыт 5 лет. Аккуратно, стерильно, вовремя.',
          schedule: {
            type: 'weekly',
            weekly: {
              Mon: [{ from: '10:00', to: '18:00' }],
              Tue: [{ from: '10:00', to: '18:00' }],
              Wed: [{ from: '10:00', to: '18:00' }],
              Thu: [{ from: '12:00', to: '20:00' }],
              Fri: [{ from: '12:00', to: '20:00' }],
              Sat: [],
              Sun: []
            }
          },
          createdAt: now,
          updatedAt: now
        }
      ],
      serviceGroups: [
        {
          id: groupId,
          name: 'Ногтевой сервис',
          sort: 1,
          services: [
            {
              id: serviceId,
              groupId,
              name: 'Маникюр классический',
              description: 'Обработка ногтей и кутикулы',
              price: 30,
              durationMinutes: 60,
              isActive: true,
              createdAt: now,
              updatedAt: now
            }
          ]
        }
      ],
      clients: [],
      bookings: []
    };
    await fs.writeFile(DB_PATH, JSON.stringify(seed, null, 2), 'utf-8');
  }
}

async function readDb(): Promise<DbShape> {
  await ensureDbFile();
  const raw = await fs.readFile(DB_PATH, 'utf-8');
  return JSON.parse(raw) as DbShape;
}

async function writeDb(db: DbShape): Promise<void> {
  await fs.writeFile(DB_PATH, JSON.stringify(db, null, 2), 'utf-8');
}

export const db = {
  async listMasters() {
    const d = await readDb();
    return d.masters;
  },
  async createMaster(input: Partial<Master>) {
    const d = await readDb();
    const now = new Date().toISOString();
    const m: Master = {
      id: crypto.randomUUID(),
      name: input.name || 'Без имени',
      phone: input.phone,
      avatarUrl: input.avatarUrl,
      isActive: input.isActive ?? true, // will fix below
      specialties: input.specialties || [],
      description: input.description,
      schedule: input.schedule || { type: 'weekly', weekly: {} },
      createdAt: now,
      updatedAt: now
    } as Master;
    d.masters.push(m);
    await writeDb(d);
    return m;
  }
};
