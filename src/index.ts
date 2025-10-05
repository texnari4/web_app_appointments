
import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { nanoid } from 'nanoid';
import { listMasters, createMaster, updateMaster, deleteMaster } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;

// Simple logger
app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - started;
    console.log(`${req.method} ${req.originalUrl} -> ${res.statusCode} (${ms}ms)`);
  });
  next();
});

app.use(express.json());
app.use('/public', express.static(path.join(__dirname, '../public')));

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Root -> NOT_FOUND (как по твоему описанию)
app.all('/', (_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

// Админка
app.get(['/admin', '/admin/'], (_req, res) => {
  res.sendFile(path.join(__dirname, '../public/admin/index.html'));
});

// Schemas
const masterCreateSchema = z.object({
  name: z.string().min(1),
  phone: z.string().optional(),
  avatarUrl: z.string().url().optional(),
  isActive: z.boolean().optional().default(true),
});

const masterUpdateSchema = z.object({
  name: z.string().min(1).optional(),
  phone: z.string().optional(),
  avatarUrl: z.string().url().optional(),
  isActive: z.boolean().optional(),
});

// API (под твоё пространство путей)
app.get('/public/api/masters', async (_req, res) => {
  try {
    const items = await listMasters();
    res.json(items);
  } catch (e) {
    console.error('GET /public/api/masters', e);
    res.status(500).json({ error: 'STORAGE_ERROR' });
  }
});

app.post('/public/api/masters', async (req, res) => {
  try {
    const data = masterCreateSchema.parse(req.body);
    const created = await createMaster({ id: nanoid(), ...data });
    res.status(201).json(created);
  } catch (e) {
    console.error('POST /public/api/masters', e);
    if (e instanceof Error) return res.status(400).json({ error: e.message });
    res.status(400).json({ error: 'BAD_REQUEST' });
  }
});

app.put('/public/api/masters/:id', async (req, res) => {
  try {
    const patch = masterUpdateSchema.parse(req.body);
    const updated = await updateMaster(req.params.id, patch);
    if (!updated) return res.status(404).json({ error: 'NOT_FOUND' });
    res.json(updated);
  } catch (e) {
    console.error('PUT /public/api/masters/:id', e);
    if (e instanceof Error) return res.status(400).json({ error: e.message });
    res.status(400).json({ error: 'BAD_REQUEST' });
  }
});

app.delete('/public/api/masters/:id', async (req, res) => {
  try {
    const ok = await deleteMaster(req.params.id);
    res.json({ ok });
  } catch (e) {
    console.error('DELETE /public/api/masters/:id', e);
    res.status(500).json({ error: 'STORAGE_ERROR' });
  }
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
