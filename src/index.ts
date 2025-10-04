import express from 'express';
import path from 'path';
import { PrismaClient } from '@prisma/client';

const app = express();
const prisma = new PrismaClient();

// Middlewares
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Static
const staticDir = path.join(__dirname, '..', 'public');
app.use(express.static(staticDir));

// Root page
app.get('/', (_req, res) => {
  res.send(`
    <main style="font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', Arial; padding:24px;">
      <h1 style="font-weight:600; letter-spacing:-.02em">Онлайн‑запись</h1>
      <p>Сервер: Express + Prisma</p>
      <pre style="background:#f5f5f7; padding:12px; border-radius:12px">
GET /api/services
POST /api/appointments
GET /admin/services (UI)
GET /admin/api/services
POST /admin/api/services
PUT /admin/api/services/:id
DELETE /admin/api/services/:id
      </pre>
      <p><a href="/admin/services">Открыть админку услуг →</a></p>
    </main>
  `);
});

/* ---------- Public API ---------- */

// Список услуг
app.get('/api/services', async (_req, res) => {
  const list = await prisma.service.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(list);
});

// Создание записи
app.post('/api/appointments', async (req, res) => {
  try {
    const { tgUserId, serviceId, startAt } = req.body || {};
    if (!serviceId || !startAt) {
      return res.status(400).json({ error: 'serviceId и startAt обязательны' });
    }
    const service = await prisma.service.findUnique({ where: { id: serviceId } });
    if (!service) return res.status(404).json({ error: 'Услуга не найдена' });

    // клиент по tgUserId (если пришёл)
    let clientId: string | undefined = undefined;
    if (tgUserId) {
      const existing = await prisma.client.findFirst({ where: { tgUserId: String(tgUserId) } });
      if (existing) clientId = existing.id;
      else {
        const created = await prisma.client.create({ data: { tgUserId: String(tgUserId) } });
        clientId = created.id;
      }
    }

    const start = new Date(startAt);
    const end = new Date(start.getTime() + service.durationMin * 60 * 1000);

    const createdAppt = await prisma.appointment.create({
      data: {
        startAt: start,
        endAt: end,
        status: 'CREATED',
        service: { connect: { id: service.id } },
        ...(clientId ? { client: { connect: { id: clientId } } } : {}),
      },
      include: { service: true, client: true },
    });

    res.json(createdAppt);
  } catch (e: any) {
    console.error('POST /api/appointments error', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

/* ---------- Admin API ---------- */

// UI
app.get('/admin/services', (_req, res) => {
  res.sendFile(path.join(staticDir, 'admin', 'services.html'));
});

// List
app.get('/admin/api/services', async (_req, res) => {
  const list = await prisma.service.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(list);
});

// Create
app.post('/admin/api/services', async (req, res) => {
  try {
    const { name, durationMin, priceCents } = req.body || {};
    if (!name) return res.status(400).json({ error: 'name_required' });
    const duration = parseInt(durationMin, 10);
    const price = parseInt(priceCents, 10);
    if (Number.isNaN(duration) || duration <= 0) return res.status(400).json({ error: 'bad_duration' });
    if (Number.isNaN(price) || price < 0) return res.status(400).json({ error: 'bad_price' });

    const created = await prisma.service.create({
      data: { name: String(name), durationMin: duration, priceCents: price }
    });
    res.json(created);
  } catch (e: any) {
    console.error('POST /admin/api/services', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

// Update
app.put('/admin/api/services/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, durationMin, priceCents } = req.body || {};
    const payload: any = {};
    if (name !== undefined) payload.name = String(name);
    if (durationMin !== undefined) payload.durationMin = parseInt(durationMin, 10);
    if (priceCents !== undefined) payload.priceCents = parseInt(priceCents, 10);

    const updated = await prisma.service.update({ where: { id }, data: payload });
    res.json(updated);
  } catch (e: any) {
    console.error('PUT /admin/api/services/:id', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

// Delete
app.delete('/admin/api/services/:id', async (req, res) => {
  try {
    const { id } = req.params;
    await prisma.service.delete({ where: { id } });
    res.json({ ok: true });
  } catch (e: any) {
    console.error('DELETE /admin/api/services/:id', e);
    res.status(500).json({ error: 'internal_error' });
  }
});

// 404 for admin static
app.use('/admin', (_req, res) => {
  res.status(404).send('Admin page not found');
});

// Start
const PORT = Number(process.env.PORT || 3000);
app.listen(PORT, () => {
  console.log(`Server listening on http://0.0.0.0:${PORT}`);
});
