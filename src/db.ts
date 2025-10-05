import fs from "fs/promises";
import path from "path";
import { nanoid } from "nanoid";
import { masterCreateSchema, masterUpdateSchema } from "./validators";
import type { Master } from "./types";

const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), "data");
const MASTERS_FILE = path.join(DATA_DIR, "masters.json");

// In-memory write lock to serialize writes
let writeQueue = Promise.resolve();

async function ensureFiles() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try { await fs.access(MASTERS_FILE); }
  catch { await fs.writeFile(MASTERS_FILE, "[]", "utf-8"); }
}

async function readJSON<T>(file: string): Promise<T> {
  await ensureFiles();
  const raw = await fs.readFile(file, "utf-8");
  return JSON.parse(raw) as T;
}

async function writeJSON(file: string, data: unknown) {
  await ensureFiles();
  const tmp = file + ".tmp";
  await fs.writeFile(tmp, JSON.stringify(data, null, 2), "utf-8");
  await fs.rename(tmp, file);
}

export async function listMasters(): Promise<Master[]> {
  return readJSON<Master[]>(MASTERS_FILE);
}

export async function createMaster(input: unknown): Promise<Master> {
  const parsed = masterCreateSchema.parse(input);
  const now = new Date().toISOString();
  const master: Master = {
    id: nanoid(),
    name: parsed.name,
    phone: parsed.phone,
    specialty: parsed.specialty,
    photoUrl: parsed.photoUrl,
    createdAt: now,
    updatedAt: now,
  };

  // Serialize writes
  await (writeQueue = writeQueue.then(async () => {
    const all = await listMasters();
    all.push(master);
    await writeJSON(MASTERS_FILE, all);
  }));

  return master;
}

export async function updateMaster(id: string, input: unknown): Promise<Master> {
  const patch = masterUpdateSchema.parse(input);
  let updated: Master | undefined;

  await (writeQueue = writeQueue.then(async () => {
    const all = await listMasters();
    const idx = all.findIndex(m => m.id === id);
    if (idx === -1) throw new Error("NOT_FOUND");
    updated = { ...all[idx], ...patch, updatedAt: new Date().toISOString() };
    all[idx] = updated!;
    await writeJSON(MASTERS_FILE, all);
  }));

  return updated!;
}

export async function deleteMaster(id: string): Promise<void> {
  await (writeQueue = writeQueue.then(async () => {
    const all = await listMasters();
    const next = all.filter(m => m.id !== id);
    await writeJSON(MASTERS_FILE, next);
  }));
}
