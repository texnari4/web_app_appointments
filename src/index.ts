import express, { Request, Response } from 'express';
import pinoHttp from 'pino-http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import { masterCreateSchema, type MasterCreateInput } from './validators.js';
import { readDb, writeDb } from './storage.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT || 8080);

app.use(pinoHttp());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// health
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// static admin
app.use('/admin', express.static(path.join(__dirname, '../public/admin'), { extensions: ['html'] }));
app.use('/', express.static(path.join(__dirname, '../public'), { extensions: ['html'] }));

// API - admin
app.get('/admin/api/masters', async (_req, res) => {
  const db = await readDb();
  res.json({ items: db.masters });
});

app.post('/admin/api/masters', async (req, res) => {
  const parsed = masterCreateSchema.safeParse(req.body as MasterCreateInput);
  if (!parsed.success) {
    return res.status(400).json({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() });
  }
  const input = parsed.data;
  const db = await readDb();
  const master = {
    id: crypto.randomUUID(),
    name: input.name,
    phone: input.phone && input.phone.length ? input.phone : undefined,
    createdAt: new Date().toISOString(),
  };
  db.masters.unshift(master);
  await writeDb(db);
  res.status(201).json(master);
});

app.delete('/admin/api/masters/:id', async (req, res) => {
  const id = req.params.id;
  const db = await readDb();
  const before = db.masters.length;
  db.masters = db.masters.filter(m => m.id !== id);
  if (db.masters.length === before) {
    return res.status(404).json({ error: 'NOT_FOUND' });
  }
  await writeDb(db);
  res.json({ ok: true });
});

// fallback 404 for API
app.use((_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
