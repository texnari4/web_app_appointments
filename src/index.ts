import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ensureDataWritable, listMasters, createMaster, updateMaster, deleteMaster } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const DATA_DIR = process.env.DATA_DIR || '/app/data';

// Simple request log
app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - started;
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl} -> ${res.statusCode} ${ms}ms`);
  });
  next();
});

app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Serve admin UI
app.use('/admin/', express.static(path.join(__dirname, '../public/admin')));

// Public API for masters
app.get('/public/api/masters', async (_req, res) => {
  try {
    const items = await listMasters();
    res.json({ items });
  } catch (e) {
    console.error('list masters error', e);
    res.status(500).json({ error: 'INTERNAL_ERROR' });
  }
});

app.post('/public/api/masters', async (req, res) => {
  try {
    const body = req.body ?? {};
    const created = await createMaster({
      name: String(body.name || '').trim(),
      phone: (body.phone ? String(body.phone).trim() : ''),
      avatarUrl: (body.avatarUrl ? String(body.avatarUrl).trim() : ''),
      isActive: body.isActive !== false
    });
    res.status(201).json(created);
  } catch (e: unknown) {
    console.error('create master error', e);
    res.status(400).json({ error: 'BAD_REQUEST' });
  }
});

app.put('/public/api/masters/:id', async (req, res) => {
  try {
    const id = String(req.params.id);
    const body = req.body ?? {};
    const updated = await updateMaster(id, body);
    if (!updated) return res.status(404).json({ error: 'NOT_FOUND' });
    res.json(updated);
  } catch (e) {
    console.error('update master error', e);
    res.status(400).json({ error: 'BAD_REQUEST' });
  }
});

app.delete('/public/api/masters/:id', async (req, res) => {
  try {
    const id = String(req.params.id);
    const ok = await deleteMaster(id);
    if (!ok) return res.status(404).json({ error: 'NOT_FOUND' });
    res.json({ ok: true });
  } catch (e) {
    console.error('delete master error', e);
    res.status(400).json({ error: 'BAD_REQUEST' });
  }
});

// Fallback 404 JSON for root and others
app.use((_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

// Start server only after ensuring data dir/file exists & writable
ensureDataWritable().then(() => {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server started on :${PORT}`);
  });
}).catch((err) => {
  console.error('Failed to ensure data dir/file', err);
  process.exit(1);
});
