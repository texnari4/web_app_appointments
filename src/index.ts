import express, { Request, Response } from 'express';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { prisma } from './prisma';
import { createMasterSchema, createServiceSchema, createAppointmentSchema } from './validators';

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const app = express();
app.use(cors());
app.use(express.json());
app.use(pinoHttp({ logger }));

app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Masters
app.get('/masters', async (_req, res) => {
  const data = await prisma.master.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(data);
});

app.post('/masters', async (req, res) => {
  const parsed = createMasterSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const master = await prisma.master.create({ data: parsed.data });
  res.status(201).json(master);
});

app.get('/masters/:id', async (req, res) => {
  const master = await prisma.master.findUnique({ where: { id: req.params.id }, include: { services: true } });
  if (!master) return res.status(404).json({ error: 'Not found' });
  res.json(master);
});

app.put('/masters/:id', async (req, res) => {
  const parsed = createMasterSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const master = await prisma.master.update({ where: { id: req.params.id }, data: parsed.data });
  res.json(master);
});

app.delete('/masters/:id', async (req, res) => {
  await prisma.master.delete({ where: { id: req.params.id } });
  res.status(204).send();
});

app.post('/masters/:id/services', async (req, res) => {
  const parsed = createServiceSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const service = await prisma.service.create({ data: { ...parsed.data, masterId: req.params.id } });
  res.status(201).json(service);
});

// Services
app.get('/services', async (_req, res) => {
  const data = await prisma.service.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(data);
});

app.post('/services', async (req, res) => {
  const parsed = createServiceSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const service = await prisma.service.create({ data: parsed.data });
  res.status(201).json(service);
});

app.get('/services/:id', async (req, res) => {
  const service = await prisma.service.findUnique({ where: { id: req.params.id } });
  if (!service) return res.status(404).json({ error: 'Not found' });
  res.json(service);
});

app.put('/services/:id', async (req, res) => {
  const parsed = createServiceSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const service = await prisma.service.update({ where: { id: req.params.id }, data: parsed.data });
  res.json(service);
});

app.delete('/services/:id', async (req, res) => {
  await prisma.service.delete({ where: { id: req.params.id } });
  res.status(204).send();
});

// Appointments
app.get('/appointments', async (req, res) => {
  const { masterId, from, to } = req.query as { masterId?: string; from?: string; to?: string };
  const where: any = {};
  if (masterId) where.masterId = masterId;
  if (from || to) {
    where.startsAt = {};
    if (from) where.startsAt.gte = new Date(from);
    if (to) where.startsAt.lte = new Date(to);
  }
  const data = await prisma.appointment.findMany({ where, orderBy: { startsAt: 'asc' } });
  res.json(data);
});

app.post('/appointments', async (req, res) => {
  const parsed = createAppointmentSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const a = parsed.data;
  const appt = await prisma.appointment.create({ data: {
    masterId: a.masterId,
    serviceId: a.serviceId,
    startsAt: new Date(a.startsAt),
    endsAt: new Date(a.endsAt),
    customerName: a.customerName,
    customerPhone: a.customerPhone
  }});
  res.status(201).json(appt);
});

app.put('/appointments/:id', async (req, res) => {
  const appt = await prisma.appointment.update({ where: { id: req.params.id }, data: req.body });
  res.json(appt);
});

app.delete('/appointments/:id', async (req, res) => {
  await prisma.appointment.delete({ where: { id: req.params.id } });
  res.status(204).send();
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  logger.info({ port }, 'Server started');
});
