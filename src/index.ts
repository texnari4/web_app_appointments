import express from 'express';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import path from 'path';
import { prisma } from './prisma';
import {
  MasterCreateSchema,
  ServiceCreateSchema,
  AppointmentCreateSchema,
} from './validators';

const PORT = Number(process.env.PORT || 8080);
const app = express();

const logger = pino();
app.use(pinoHttp({ logger }));
app.use(cors());
app.use(express.json());

// Static admin
const publicDir = path.join(__dirname, '..', 'public');
app.use('/admin', express.static(path.join(publicDir, 'admin')));

app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Masters
app.get('/api/masters', async (_req, res) => {
  const items = await prisma.master.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(items);
});

app.post('/api/masters', async (req, res) => {
  const parsed = MasterCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const created = await prisma.master.create({ data: parsed.data });
  res.status(201).json(created);
});

// Services
app.get('/api/services', async (_req, res) => {
  const items = await prisma.service.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(items);
});

app.post('/api/services', async (req, res) => {
  const parsed = ServiceCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const created = await prisma.service.create({ data: parsed.data });
  res.status(201).json(created);
});

// Appointments
app.get('/api/appointments', async (_req, res) => {
  const items = await prisma.appointment.findMany({
    orderBy: { startsAt: 'desc' },
    include: { master: true, service: true },
  });
  res.json(items);
});

app.post('/api/appointments', async (req, res) => {
  const parsed = AppointmentCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { masterId, serviceId, startsAt, endsAt, customerName, customerPhone } = parsed.data;

  // basic overlap check per master
  const overlap = await prisma.appointment.findFirst({
    where: {
      masterId,
      OR: [
        { startsAt: { lt: new Date(endsAt) }, endsAt: { gt: new Date(startsAt) } },
      ],
    },
  });
  if (overlap) return res.status(409).json({ error: 'Time slot overlaps existing appointment.' });

  const created = await prisma.appointment.create({
    data: {
      masterId,
      serviceId,
      startsAt: new Date(startsAt),
      endsAt: new Date(endsAt),
      customerName,
      customerPhone,
    },
  });
  res.status(201).json(created);
});

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
