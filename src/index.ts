import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { db } from './db.js';

const PORT = Number(process.env.PORT || 8080);
const app = express();

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
app.use(pinoHttp({ logger }));

app.use(cors());
app.use(express.json());
app.use('/public', express.static(path.join(process.cwd(), 'public')));

app.get('/health', (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

// Masters
app.get('/public/api/masters', async (_req, res) => {
  res.json({ items: await db.listMasters() });
});
app.post('/public/api/masters', async (req, res) => {
  const body = req.body;
  if (!body?.name || !body?.phone) return res.status(400).json({ error: 'name and phone required' });
  const saved = await db.addMaster({ 
    name: body.name, phone: body.phone, avatarUrl: body.avatarUrl, isActive: body.isActive ?? true,
    about: body.about, specialties: body.specialties, schedule: body.schedule
  });
  res.status(201).json(saved);
});
app.put('/public/api/masters/:id', async (req, res) => {
  const saved = await db.updateMaster(req.params.id, req.body ?? {});
  if (!saved) return res.status(404).json({ error: 'not found' });
  res.json(saved);
});
app.delete('/public/api/masters/:id', async (req, res) => {
  await db.deleteMaster(req.params.id);
  res.status(204).end();
});

// Service Groups
app.get('/public/api/service-groups', async (_req, res) => {
  res.json({ items: await db.listGroups() });
});
app.post('/public/api/service-groups', async (req, res) => {
  const body = req.body;
  if (!body?.title) return res.status(400).json({ error: 'title required' });
  const saved = await db.addGroup({ title: body.title, description: body.description });
  res.status(201).json(saved);
});
app.put('/public/api/service-groups/:id', async (req, res) => {
  const saved = await db.updateGroup(req.params.id, req.body ?? {});
  if (!saved) return res.status(404).json({ error: 'not found' });
  res.json(saved);
});
app.delete('/public/api/service-groups/:id', async (req, res) => {
  await db.deleteGroup(req.params.id);
  res.status(204).end();
});

// Services
app.get('/public/api/services', async (_req, res) => {
  res.json({ items: await db.listServices() });
});
app.post('/public/api/services', async (req, res) => {
  const b = req.body;
  if (!b?.groupId || !b?.title || typeof b?.price !== 'number' || typeof b?.durationMin !== 'number') {
    return res.status(400).json({ error: 'groupId, title, price(number), durationMin(number) required' });
  }
  const saved = await db.addService({ groupId: b.groupId, title: b.title, description: b.description, price: b.price, durationMin: b.durationMin });
  res.status(201).json(saved);
});
app.put('/public/api/services/:id', async (req, res) => {
  const saved = await db.updateService(req.params.id, req.body ?? {});
  if (!saved) return res.status(404).json({ error: 'not found' });
  res.json(saved);
});
app.delete('/public/api/services/:id', async (req, res) => {
  await db.deleteService(req.params.id);
  res.status(204).end();
});

// Admin UI
app.get(['/','/admin','/admin/'], (_req, res) => {
  res.sendFile(path.join(process.cwd(), 'public/admin/index.html'));
});

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
