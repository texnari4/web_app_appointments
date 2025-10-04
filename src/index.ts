import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import { PrismaClient } from '@prisma/client';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const prisma = new PrismaClient();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, '../public')));

app.get('/', (_req, res) => {
  res.type('text/plain').send(
`Онлайн‑запись
Сервер: Express + Prisma

GET  /api/services
POST /api/appointments
GET  /admin/api/services
POST /admin/api/services
PUT  /admin/api/services/:id
DELETE /admin/api/services/:id

Админка: /admin/services
`);
});

// PUBLIC API
app.get('/api/services', async (_req, res) => {
  const items = await prisma.service.findMany({ orderBy: { name: 'asc' } });
  res.json(items);
});

app.post('/api/appointments', async (req, res) => {
  try {
    const { tgUserId, serviceId, startAt } = req.body ?? {};
    if (!serviceId || !startAt) return res.status(400).json({ error: 'serviceId и startAt обязательны' });

    const service = await prisma.service.findUnique({ where: { id: serviceId } });
    if (!service) return res.status(404).json({ error: 'Услуга не найдена' });

    const start = new Date(startAt);
    if (isNaN(start.getTime())) return res.status(400).json({ error: 'Некорректный startAt' });
    const end = new Date(start.getTime() + service.durationMin * 60_000);

    let clientId: string | null = null;
    if (tgUserId) {
      const existing = await prisma.client.findFirst({ where: { tgUserId: String(tgUserId) } });
      if (existing) clientId = existing.id;
      else {
        const created = await prisma.client.create({ data: { tgUserId: String(tgUserId) } });
        clientId = created.id;
      }
    }

    const appt = await prisma.appointment.create({
      data: {
        startAt: start,
        endAt: end,
        status: 'CREATED',
        ...(clientId ? { client: { connect: { id: clientId } } } : {}),
        service: { connect: { id: serviceId } },
      },
      include: { service: true, client: true },
    });

    res.status(201).json(appt);
  } catch (e: any) {
    console.error(e);
    res.status(500).json({ error: 'Ошибка создания записи', detail: e?.message });
  }
});

// ADMIN PAGES
app.get('/admin/services', (_req, res) => {
  res.sendFile(path.join(__dirname, '../public/admin/services.html'));
});

app.get('/admin/api/services', async (_req, res) => {
  const items = await prisma.service.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(items);
});

app.post('/admin/api/services', async (req, res) => {
  try {
    const { name, durationMin, priceCents } = req.body ?? {};
    if (!name || durationMin == null || priceCents == null) {
      return res.status(400).json({ error: 'name, durationMin, priceCents обязательны' });
    }
    const created = await prisma.service.create({
      data: {
        name: String(name).trim(),
        durationMin: Number(durationMin),
        priceCents: Number(priceCents),
      }
    });
    res.status(201).json(created);
  } catch (e: any) {
    console.error(e);
    res.status(500).json({ error: 'Не удалось создать услугу', detail: e?.message });
  }
});

app.put('/admin/api/services/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, durationMin, priceCents } = req.body ?? {};
    const updated = await prisma.service.update({
      where: { id },
      data: {
        ...(name != null ? { name: String(name).trim() } : {}),
        ...(durationMin != null ? { durationMin: Number(durationMin) } : {}),
        ...(priceCents != null ? { priceCents: Number(priceCents) } : {}),
      }
    });
    res.json(updated);
  } catch (e: any) {
    console.error(e);
    res.status(500).json({ error: 'Не удалось обновить услугу', detail: e?.message });
  }
});

app.delete('/admin/api/services/:id', async (req, res) => {
  try {
    const { id } = req.params;
    await prisma.service.delete({ where: { id } });
  } catch (e: any) {
    console.error(e);
    return res.status(500).json({ error: 'Не удалось удалить услугу', detail: e?.message });
  }
  res.status(204).send();
});

const PORT = process.env.PORT ? Number(process.env.PORT) : 3000;
app.listen(PORT, () => {
  console.log(`Server listening on :${PORT}`);
});
