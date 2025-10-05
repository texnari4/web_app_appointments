import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pinoHTTP from 'pino-http';

import {
  listMasters, createMaster, updateMaster, deleteMaster,
  listServiceGroups, createServiceGroup, updateServiceGroup, deleteServiceGroup,
  listServices, createService, updateService, deleteService
} from './db.js';

const app = express();
const PORT = Number(process.env.PORT || 8080);

app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(pinoHTTP());

// static admin
app.use('/admin', express.static(path.join(process.cwd(), 'public', 'admin'), { extensions: ['html'] }));
// public (if needed)
app.use('/', express.static(path.join(process.cwd(), 'public'), { extensions: ['html'] }));

app.get('/health', (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

// Masters
app.get('/public/api/masters', async (_req, res) => {
  res.json({ items: await listMasters() });
});
app.post('/public/api/masters', async (req, res) => {
  const created = await createMaster(req.body ?? {});
  res.status(201).json(created);
});
app.put('/public/api/masters/:id', async (req, res) => {
  const upd = await updateMaster(req.params.id, req.body ?? {});
  if (!upd) return res.status(404).json({ error: 'Not found' });
  res.json(upd);
});
app.delete('/public/api/masters/:id', async (req, res) => {
  await deleteMaster(req.params.id);
  res.json({ ok: true });
});

// Service Groups
app.get('/public/api/service-groups', async (_req, res) => {
  res.json({ items: await listServiceGroups() });
});
app.post('/public/api/service-groups', async (req, res) => {
  const created = await createServiceGroup(req.body ?? {});
  res.status(201).json(created);
});
app.put('/public/api/service-groups/:id', async (req, res) => {
  const upd = await updateServiceGroup(req.params.id, req.body ?? {});
  if (!upd) return res.status(404).json({ error: 'Not found' });
  res.json(upd);
});
app.delete('/public/api/service-groups/:id', async (req, res) => {
  await deleteServiceGroup(req.params.id);
  res.json({ ok: true });
});

// Services
app.get('/public/api/services', async (_req, res) => {
  res.json({ items: await listServices() });
});
app.post('/public/api/services', async (req, res) => {
  const created = await createService(req.body ?? {});
  res.status(201).json(created);
});
app.put('/public/api/services/:id', async (req, res) => {
  const upd = await updateService(req.params.id, req.body ?? {});
  if (!upd) return res.status(404).json({ error: 'Not found' });
  res.json(upd);
});
app.delete('/public/api/services/:id', async (req, res) => {
  await deleteService(req.params.id);
  res.json({ ok: true });
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
