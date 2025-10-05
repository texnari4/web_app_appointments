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
async function ensureDataDir() {
    await mkdir(DATA_DIR, { recursive: true });
}
async function filePath(kind) {
    await ensureDataDir();
    return path.join(DATA_DIR, FILES[kind]);
}
async function readJson(kind) {
    const fp = await filePath(kind);
    try {
        await access(fp);
    }
    catch {
        await writeFile(fp, '[]', 'utf-8');
    }
    const raw = await readFile(fp, 'utf-8');
    try {
        const arr = JSON.parse(raw);
        if (Array.isArray(arr))
            return arr;
        return [];
    }
    catch {
        return [];
    }
}
async function writeJson(kind, arr) {
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
    async listMasters() { return readJson('masters'); },
    async upsertMaster(payload) {
        const list = await readJson('masters');
        if (payload.id) {
            const idx = list.findIndex(x => x.id === payload.id);
            if (idx >= 0) {
                list[idx] = { ...list[idx], ...payload, updatedAt: nowISO() };
            }
            else {
                const now = nowISO();
                list.push({ id: payload.id, name: payload.name || '', isActive: true, createdAt: now, updatedAt: now, ...payload });
            }
        }
        else {
            const now = nowISO();
            list.push({ id: newId(), name: payload.name || '', isActive: true, createdAt: now, updatedAt: now, ...payload });
        }
        await writeJson('masters', list);
        return list[list.length - 1];
    },
    async deleteMaster(id) {
        const list = await readJson('masters');
        const next = list.filter(x => x.id !== id);
        await writeJson('masters', next);
        return { ok: true };
    },
    async listServices() { return readJson('services'); },
    async upsertService(payload) {
        const list = await readJson('services');
        const now = nowISO();
        if (payload.id) {
            const i = list.findIndex(x => x.id === payload.id);
            if (i >= 0)
                list[i] = { ...list[i], ...payload, updatedAt: now };
            else
                list.push({ id: payload.id, title: payload.title || '', group: payload.group || 'Общее', price: payload.price ?? 0, durationMin: payload.durationMin ?? 60, createdAt: now, updatedAt: now, ...payload });
        }
        else {
            list.push({ id: newId(), title: payload.title || '', group: payload.group || 'Общее', price: payload.price ?? 0, durationMin: payload.durationMin ?? 60, createdAt: now, updatedAt: now, ...payload });
        }
        await writeJson('services', list);
        return list[list.length - 1];
    },
    async deleteService(id) {
        const list = await readJson('services');
        const next = list.filter(x => x.id !== id);
        await writeJson('services', next);
        return { ok: true };
    },
    async listAppointments() { return readJson('appointments'); },
    async upsertAppointment(payload) {
        const list = await readJson('appointments');
        const now = nowISO();
        if (payload.id) {
            const i = list.findIndex(x => x.id === payload.id);
            if (i >= 0)
                list[i] = { ...list[i], ...payload, updatedAt: now };
            else
                list.push({ id: payload.id, createdAt: now, updatedAt: now, ...payload });
        }
        else {
            list.push({ id: newId(), createdAt: now, updatedAt: now, ...payload });
        }
        await writeJson('appointments', list);
        return list[list.length - 1];
    },
    async deleteAppointment(id) {
        const list = await readJson('appointments');
        const next = list.filter(x => x.id !== id);
        await writeJson('appointments', next);
        return { ok: true };
    },
    async listClients() { return readJson('clients'); },
    async upsertClient(payload) {
        const list = await readJson('clients');
        const now = nowISO();
        if (payload.id) {
            const i = list.findIndex(x => x.id === payload.id);
            if (i >= 0)
                list[i] = { ...list[i], ...payload, updatedAt: now };
            else
                list.push({ id: payload.id, name: payload.name || '', createdAt: now, updatedAt: now, ...payload });
        }
        else {
            list.push({ id: newId(), name: payload.name || '', createdAt: now, updatedAt: now, ...payload });
        }
        await writeJson('clients', list);
        return list[list.length - 1];
    },
    async deleteClient(id) {
        const list = await readJson('clients');
        const next = list.filter(x => x.id !== id);
        await writeJson('clients', next);
        return { ok: true };
    }
};
