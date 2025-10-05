
import express, { Request, Response, NextFunction } from 'express';
import path from 'path';
import { nanoid } from 'nanoid';
import { z } from 'zod';
import { listMasters, createMaster, updateMaster, deleteMaster } from './db.js';

const app = express();
const PORT = process.env.PORT || 8080;

app.use(express.json());
app.use('/public', express.static(path.join(process.cwd(), 'public')));

// Tiny logger
app.use((req, _res, next) => {
  const start = Date.now();
  const end = () => {
    const ms = Date.now() - start;
    console.log(`[req] ${req.method} ${req.originalUrl} ${ms}ms`);
  };
  _res.once('finish', end);
  next();
});

app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

app.get('/', (_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

// Admin UI
app.get('/admin/', (_req, res) => {
  res.sendFile(path.join(process.cwd(), 'public', 'admin', 'index.html'));
});

// Schemas
const masterCreateSchema = z.object({
  name: z.string().min(1),
  phone: z.string().optional(),
  avatarUrl: z.string().url().optional(),
  isActive: z.boolean().default(true),
});

const masterUpdateSchema = masterCreateSchema.partial();

// API
app.get('/public/api/masters', async (_req, res, next) => {
  try {
    const items = await listMasters();
    res.json({ items });
  } catch (e) { next(e); }
});

app.post('/public/api/masters', async (req, res, next) => {
  try {
    const parsed = masterCreateSchema.parse(req.body);
    const created = await createMaster({ id: nanoid(), ...parsed });
    res.status(201).json(created);
  } catch (e) { next(e); }
});

app.put('/public/api/masters/:id', async (req, res, next) => {
  try {
    const patch = masterUpdateSchema.parse(req.body);
    const updated = await updateMaster(req.params.id, patch);
    if (!updated) return res.status(404).json({ error: 'NOT_FOUND' });
    res.json(updated);
  } catch (e) { next(e); }
});

app.delete('/public/api/masters/:id', async (req, res, next) => {
  try {
    const ok = await deleteMaster(req.params.id);
    res.json({ ok });
  } catch (e) { next(e); }
});

// Error handler
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  console.error('[error]', err);
  res.status(500).json({ error: 'INTERNAL', detail: err?.message ?? String(err) });
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
