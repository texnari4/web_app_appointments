import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pinoHttp from 'pino-http';

import { listMasters, createMaster, replaceMasters, type Master } from './db.js';

const app = express();
const PORT = Number(process.env.PORT || 8080);
const PUBLIC_DIR = path.join(process.cwd(), 'public');

app.use(pinoHttp());
app.use(cors());
app.use(express.json());
app.use('/public', express.static(PUBLIC_DIR, { fallthrough: true }));

app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Admin page
app.get(['/admin', '/admin/'], (_req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, 'admin', 'index.html'));
});

// Public API: masters
app.get(['/public/api/masters', '/api/masters'], async (_req, res) => {
  try {
    const items = await listMasters();
    res.json({ items });
  } catch (e) {
    res.status(500).json({ error: 'failed_to_list_masters' });
  }
});

app.post(['/public/api/masters', '/api/masters'], async (req, res) => {
  try {
    const body = req.body as Partial<Master>;
    if (!body?.name || !body?.phone) {
      return res.status(400).json({ error: 'name_and_phone_required' });
    }
    const created = await createMaster({
      name: body.name,
      phone: body.phone,
      avatarUrl: body.avatarUrl,
      specialties: body.specialties ?? [],
      description: body.description,
      schedule: body.schedule,
      isActive: body.isActive ?? true
    });
    res.status(201).json(created);
  } catch (e) {
    res.status(500).json({ error: 'failed_to_create_master' });
  }
});

// Simple admin fetch to show list (kept minimal)
app.get('/admin/api/masters', async (_req, res) => {
  const items = await listMasters();
  res.json(items);
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server started on :${PORT}`);
});
