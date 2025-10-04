import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { prisma } from './prisma.js';
import { serviceCreateSchema, appointmentCreateSchema } from './validators.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(cors());
app.use(express.json());

const PORT = Number(process.env.PORT || 8080);
const SLOT_STEP_MIN = Number(process.env.SLOT_STEP_MIN || 30);

app.get('/health', (_req, res) => {
  res.json({ ok: true, time: new Date().toISOString() });
});

// Serve minimal admin UI
app.use('/admin', express.static(path.join(__dirname, '../public/admin')));

// Services CRUD
app.get('/api/services', async (_req, res) => {
  const items = await prisma.service.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(items);
});

app.post('/api/services', async (req, res) => {
  const parsed = serviceCreateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }
  const created = await prisma.service.create({ data: parsed.data });
  res.status(201).json(created);
});

app.put('/api/services/:id', async (req, res) => {
  const id = req.params.id;
  const parsed = serviceCreateSchema.partial().safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }
  try {
    const updated = await prisma.service.update({ where: { id }, data: parsed.data });
    res.json(updated);
  } catch (e) {
    res.status(404).json({ error: 'Service not found' });
  }
});

app.delete('/api/services/:id', async (req, res) => {
  const id = req.params.id;
  try {
    const removed = await prisma.service.delete({ where: { id } });
    res.json(removed);
  } catch {
    res.status(404).json({ error: 'Service not found' });
  }
});

// Appointments
app.get('/api/appointments', async (_req, res) => {
  const items = await prisma.appointment.findMany({
    orderBy: { startAt: 'asc' },
    include: { client: true, service: true, master: true }
  });
  res.json(items);
});

app.post('/api/appointments', async (req, res) => {
  const parsed = appointmentCreateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }
  const data = parsed.data;

  // resolve clientId (create or use existing)
  let clientId = data.clientId;
  if (!clientId && data.client) {
    if (data.client.tgUserId) {
      const existing = await prisma.client.findUnique({
        where: { tgUserId: data.client.tgUserId }
      });
      if (existing) clientId = existing.id;
    }
    if (!clientId) {
      const created = await prisma.client.create({ data: {
        name: data.client.name,
        phone: data.client.phone,
        tgUserId: data.client.tgUserId
      }});
      clientId = created.id;
    }
  }
  if (!clientId) {
    return res.status(400).json({ error: 'clientId or client is required' });
  }

  const service = await prisma.service.findUnique({ where: { id: data.serviceId } });
  if (!service || !service.isActive) {
    return res.status(400).json({ error: 'Service not found or inactive' });
  }

  const startAt = new Date(data.startAt);
  if (isNaN(startAt.getTime())) {
    return res.status(400).json({ error: 'Invalid startAt' });
  }
  // Snap to slot step
  const minutes = startAt.getUTCMinutes();
  const snapped = new Date(startAt);
  const remainder = minutes % SLOT_STEP_MIN;
  if (remainder !== 0) {
    snapped.setUTCMinutes(minutes - remainder, 0, 0);
  }
  const endAt = new Date(snapped.getTime() + service.durationMin * 60_000);

  // Check overlaps for master (if provided) and client
  const overlap = await prisma.appointment.findFirst({
    where: {
      OR: [
        { clientId, startAt: { lt: endAt }, endAt: { gt: snapped } },
        data.masterId ? { masterId: data.masterId, startAt: { lt: endAt }, endAt: { gt: snapped } } : undefined
      ].filter(Boolean) as any
    }
  });
  if (overlap) {
    return res.status(409).json({ error: 'Slot is not available' });
  }

  const created = await prisma.appointment.create({
    data: {
      clientId,
      serviceId: data.serviceId,
      masterId: data.masterId,
      startAt: snapped,
      endAt
    },
    include: { client: true, service: true, master: true }
  });

  res.status(201).json(created);
});

// Root
app.get('/', (_req, res) => {
  res.redirect('/admin');
});

// Boot
app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
