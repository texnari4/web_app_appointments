import express from 'express';
import cors from 'cors';
import { PrismaClient, AppointmentStatus } from '@prisma/client';
import { tgRouter, installWebhook } from './telegram';

const prisma = new PrismaClient();
const app = express();

app.use(cors());
app.use(express.json());

// Basic home page
app.get('/', (_req, res) => {
  res.type('html').send(`
    <h1>Онлайн‑запись</h1>
    <p>Сервер: Express + Prisma</p>
    <ul>
      <li>GET /api/services</li>
      <li>POST /api/appointments</li>
      <li>GET /admin/api/services</li>
      <li>POST /admin/api/services</li>
      <li>PUT /admin/api/services/:id</li>
      <li>DELETE /admin/api/services/:id</li>
    </ul>
  `);
});

// Public API
app.get('/api/services', async (_req, res) => {
  try {
    const services = await prisma.service.findMany({
      select: { id: true, name: true, durationMin: true, priceCents: true },
      orderBy: { name: 'asc' },
    });
    res.json({ ok: true, data: services });
  } catch (err: any) {
    console.error('[api] services error', err);
    res.status(500).json({ ok: false, error: 'INTERNAL' });
  }
});

// Create appointment
app.post('/api/appointments', async (req, res) => {
  try {
    const { serviceId, staffId, startAt, client } = req.body as {
      serviceId?: string;
      staffId?: string;
      startAt?: string;
      client?: { tgUserId?: string; firstName?: string; lastName?: string };
    };

    if (!serviceId || !staffId || !startAt) {
      return res.status(400).json({ ok: false, error: 'MISSING_FIELDS' });
    }

    const service = await prisma.service.findUnique({ where: { id: serviceId } });
    if (!service) return res.status(404).json({ ok: false, error: 'SERVICE_NOT_FOUND' });

    let clientConnect:
      | { connect: { id: string } }
      | { create: { tgUserId?: string | null; firstName?: string | null; lastName?: string | null } }
      | undefined;

    if (client?.tgUserId) {
      // tgUserId у нас НЕ unique по схеме, поэтому ищем через findFirst
      const existing = await prisma.client.findFirst({ where: { tgUserId: client.tgUserId } });
      if (existing) clientConnect = { connect: { id: existing.id } };
      else clientConnect = {
        create: {
          tgUserId: client.tgUserId,
          firstName: client.firstName ?? null,
          lastName: client.lastName ?? null,
        },
      };
    }

    const start = new Date(startAt);
    const end = new Date(start.getTime() + (service.durationMin ?? 30) * 60_000);

    const created = await prisma.appointment.create({
      data: {
        startAt: start,
        endAt: end,
        status: AppointmentStatus.CREATED,
        ...(clientConnect ? { client: clientConnect } : {}),
        service: { connect: { id: serviceId } },
        staff: { connect: { id: staffId } },
      },
      include: {
        service: true,
        staff: true,
        client: true,
      },
    });

    res.json({ ok: true, data: created });
  } catch (err: any) {
    console.error('[api] create appointment error', err);
    res.status(500).json({ ok: false, error: 'INTERNAL' });
  }
});

// --- Admin JSON API (без авторизации пока) ---
app.get('/admin/api/services', async (_req, res) => {
  try {
    const items = await prisma.service.findMany({
      orderBy: [{ name: 'asc' }],
    });
    res.json({ ok: true, data: items });
  } catch (err) {
    console.error('[admin] list services', err);
    res.status(500).json({ ok: false, error: 'INTERNAL' });
  }
});

app.post('/admin/api/services', async (req, res) => {
  try {
    const { name, durationMin, priceCents, description } = req.body as {
      name: string;
      durationMin: number;
      priceCents: number;
      description?: string | null;
    };
    if (!name || !durationMin || priceCents == null) {
      return res.status(400).json({ ok: false, error: 'MISSING_FIELDS' });
    }
    const created = await prisma.service.create({
      data: { name, durationMin, priceCents, description: description ?? null },
    });
    res.status(201).json({ ok: true, data: created });
  } catch (err) {
    console.error('[admin] create service', err);
    res.status(500).json({ ok: false, error: 'INTERNAL' });
  }
});

app.put('/admin/api/services/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, durationMin, priceCents, description } = req.body as {
      name?: string;
      durationMin?: number;
      priceCents?: number;
      description?: string | null;
    };
    const updated = await prisma.service.update({
      where: { id },
      data: { name, durationMin, priceCents, description: description ?? undefined },
    });
    res.json({ ok: true, data: updated });
  } catch (err) {
    console.error('[admin] update service', err);
    res.status(500).json({ ok: false, error: 'INTERNAL' });
  }
});

app.delete('/admin/api/services/:id', async (req, res) => {
  try {
    const { id } = req.params;
    await prisma.service.delete({ where: { id } });
    res.json({ ok: true });
  } catch (err) {
    console.error('[admin] delete service', err);
    res.status(500).json({ ok: false, error: 'INTERNAL' });
  }
});

// Telegram
app.use('/tg', tgRouter);

// Start
const PORT = Number(process.env.PORT || 8080);

app.listen(PORT, async () => {
  console.log(`[http] listening on :${PORT}`);
  try {
    await installWebhook(process.env.PUBLIC_BASE_URL || '');
  } catch (e) {
    console.error('[tg] setWebhook failed', e);
  }
});