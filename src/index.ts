
import express from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';
import { prisma } from './prisma';
import {
  metaCreateSchema,
  masterCreateSchema,
  serviceCreateSchema,
  appointmentCreateSchema,
  linkServiceSchema,
} from './validators';

const app = express();
const port = Number(process.env.PORT || 8080);

app.use(cors());
app.use(express.json());
app.use(pinoHttp());

app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// ---- Meta ----
app.get('/meta/:key', async (req, res) => {
  const item = await prisma.appMeta.findUnique({ where: { key: req.params.key } });
  if (!item) return res.status(404).json({ error: 'Not found' });
  res.json(item);
});

app.post('/meta', async (req, res) => {
  const parsed = metaCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { key, value } = parsed.data;
  const saved = await prisma.appMeta.upsert({
    where: { key },
    create: { key, value },
    update: { value },
  });
  res.status(201).json(saved);
});

// ---- Masters ----
app.get('/masters', async (_req, res) => {
  const items = await prisma.master.findMany({ include: { services: true } });
  res.json(items);
});

app.post('/masters', async (req, res) => {
  const parsed = masterCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const created = await prisma.master.create({ data: parsed.data });
  res.status(201).json(created);
});

app.get('/masters/:id', async (req, res) => {
  const id = Number(req.params.id);
  const item = await prisma.master.findUnique({ where: { id }, include: { services: true } });
  if (!item) return res.status(404).json({ error: 'Not found' });
  res.json(item);
});

app.put('/masters/:id', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = masterCreateSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const updated = await prisma.master.update({ where: { id }, data: parsed.data });
  res.json(updated);
});

app.delete('/masters/:id', async (req, res) => {
  const id = Number(req.params.id);
  await prisma.master.delete({ where: { id } }).catch(() => null);
  res.status(204).end();
});

// Link service to master
app.post('/masters/:id/services', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = linkServiceSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { serviceId } = parsed.data;
  const updated = await prisma.master.update({
    where: { id },
    data: { services: { connect: { id: serviceId } } },
    include: { services: true },
  });
  res.json(updated);
});

// ---- Services ----
app.get('/services', async (_req, res) => {
  const items = await prisma.service.findMany();
  res.json(items);
});

app.post('/services', async (req, res) => {
  const parsed = serviceCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const created = await prisma.service.create({ data: parsed.data });
  res.status(201).json(created);
});

app.get('/services/:id', async (req, res) => {
  const id = Number(req.params.id);
  const item = await prisma.service.findUnique({ where: { id } });
  if (!item) return res.status(404).json({ error: 'Not found' });
  res.json(item);
});

app.put('/services/:id', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = serviceCreateSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const updated = await prisma.service.update({ where: { id }, data: parsed.data });
  res.json(updated);
});

app.delete('/services/:id', async (req, res) => {
  const id = Number(req.params.id);
  await prisma.service.delete({ where: { id } }).catch(() => null);
  res.status(204).end();
});

// ---- Appointments ----
app.get('/appointments', async (req, res) => {
  const masterId = req.query.masterId ? Number(req.query.masterId) : undefined;
  const from = req.query.from ? new Date(String(req.query.from)) : undefined;
  const to = req.query.to ? new Date(String(req.query.to)) : undefined;

  const where: any = {};
  if (masterId) where.masterId = masterId;
  if (from || to) where.startsAt = { gte: from, lte: to };

  const items = await prisma.appointment.findMany({
    where,
    orderBy: { startsAt: 'asc' },
    include: { master: true, service: true },
  });
  res.json(items);
});

app.post('/appointments', async (req, res) => {
  const parsed = appointmentCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const data = parsed.data;
  // Ensure master and service exist
  const [m, s] = await Promise.all([
    prisma.master.findUnique({ where: { id: data.masterId } }),
    prisma.service.findUnique({ where: { id: data.serviceId } }),
  ]);
  if (!m) return res.status(400).json({ error: 'Master not found' });
  if (!s) return res.status(400).json({ error: 'Service not found' });

  const created = await prisma.appointment.create({ data });
  res.status(201).json(created);
});

app.put('/appointments/:id', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = appointmentCreateSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const updated = await prisma.appointment.update({ where: { id }, data: parsed.data });
  res.json(updated);
});

app.delete('/appointments/:id', async (req, res) => {
  const id = Number(req.params.id);
  await prisma.appointment.delete({ where: { id } }).catch(() => null);
  res.status(204).end();
});

app.listen(port, () => {
  console.log(`Server started on :${port}`);
});
