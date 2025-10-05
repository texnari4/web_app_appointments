
import express, { Request, Response } from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import { z } from 'zod';
import { listMasters, createMaster, updateMaster, deleteMaster } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT ? parseInt(process.env.PORT) : 8080;

app.use(express.json());
app.use('/public', express.static(path.join(__dirname, '../public')));

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Root -> not found in mini app context, but keep explicit
app.all('/', (_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

// Admin page
app.get('/admin/', (_req, res) => {
  res.sendFile(path.join(__dirname, '../public/admin/index.html'));
});

// Schemas
const MasterCreateSchema = z.object({
  name: z.string().min(1),
  phone: z.string().optional(),
  about: z.string().optional(),
});

const MasterUpdateSchema = z.object({
  name: z.string().min(1).optional(),
  phone: z.string().optional(),
  about: z.string().optional(),
});

// API
app.get('/public/api/masters', async (_req, res) => {
  const data = await listMasters();
  res.json({ items: data });
});

app.post('/public/api/masters', async (req, res) => {
  try {
    const payload = MasterCreateSchema.parse(req.body);
    const created = await createMaster(payload);
    res.status(201).json(created);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Unknown error';
    res.status(400).json({ error: msg });
  }
});

app.patch('/public/api/masters/:id', async (req, res) => {
  try {
    const patch = MasterUpdateSchema.parse(req.body);
    const updated = await updateMaster(req.params.id, patch);
    if (!updated) return res.status(404).json({ error: 'Not found' });
    res.json(updated);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Unknown error';
    res.status(400).json({ error: msg });
  }
});

app.delete('/public/api/masters/:id', async (req, res) => {
  const ok = await deleteMaster(req.params.id);
  res.json({ ok });
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
