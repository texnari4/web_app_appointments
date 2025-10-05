import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';

import {
  listMasters, createMaster, updateMaster, deleteMaster,
  listServices, createService, updateService, deleteService,
  listServiceGroups, upsertServiceGroup, deleteServiceGroup
} from './db.js';

const app = express();
const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
app.use(pinoHttp({ logger }));
app.use(cors());
app.use(express.json());
app.use('/public', express.static(path.join(process.cwd(), 'public')));

const PORT = Number(process.env.PORT || 8080);

app.get('/health', (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

// ------- Masters
app.get(['/public/api/masters', '/api/masters'], async (_req, res) => {
  res.json({ items: await listMasters() });
});

app.post(['/public/api/masters', '/api/masters'], async (req, res) => {
  try {
    const { name, phone, avatarUrl, isActive = true, description, specialties, schedule } = req.body || {};
    if (!name || !phone) return res.status(400).json({ error: 'name and phone required' });
    const created = await createMaster({ name, phone, avatarUrl, isActive, description, specialties, schedule, createdAt: '', updatedAt: '', id: '' } as any);
    res.status(201).json(created);
  } catch (e: any) {
    req.log?.error(e);
    res.status(500).json({ error: 'failed to create master' });
  }
});

app.patch(['/public/api/masters/:id', '/api/masters/:id'], async (req, res) => {
  const { id } = req.params as { id: string };
  const updated = await updateMaster(id, req.body || {});
  if (!updated) return res.status(404).json({ error: 'not found' });
  res.json(updated);
});

app.delete(['/public/api/masters/:id', '/api/masters/:id'], async (req, res) => {
  const { id } = req.params as { id: string };
  const ok = await deleteMaster(id);
  res.json({ ok });
});

// ------- Service Groups
app.get(['/public/api/service-groups', '/api/service-groups'], async (_req, res) => {
  res.json({ items: await listServiceGroups() });
});

app.post(['/public/api/service-groups', '/api/service-groups'], async (req, res) => {
  const { id, name, order } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name required' });
  const item = await upsertServiceGroup({ id, name, order });
  res.status(201).json(item);
});

app.delete(['/public/api/service-groups/:id', '/api/service-groups/:id'], async (req, res) => {
  const { id } = req.params as { id: string };
  const ok = await deleteServiceGroup(id);
  res.json({ ok });
});

// ------- Services
app.get(['/public/api/services', '/api/services'], async (_req, res) => {
  res.json({ items: await listServices() });
});

app.post(['/public/api/services', '/api/services'], async (req, res) => {
  const { groupId, title, description, price, durationMin } = req.body || {};
  if (!groupId || !title || typeof price !== 'number' || typeof durationMin !== 'number') {
    return res.status(400).json({ error: 'groupId, title, price(number), durationMin(number) required' });
  }
  const created = await createService({ groupId, title, description, price, durationMin, createdAt: '', updatedAt: '', id: '' } as any);
  res.status(201).json(created);
});

app.patch(['/public/api/services/:id', '/api/services/:id'], async (req, res) => {
  const { id } = req.params as { id: string };
  const updated = await updateService(id, req.body || {});
  if (!updated) return res.status(404).json({ error: 'not found' });
  res.json(updated);
});

app.delete(['/public/api/services/:id', '/api/services/:id'], async (req, res) => {
  const { id } = req.params as { id: string };
  const ok = await deleteService(id);
  res.json({ ok });
});

// Admin (inline v4)
app.get(['/admin', '/admin/'], (_req, res) => {
  res.sendFile(path.join(process.cwd(), 'public', 'admin', 'index.html'));
});

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
