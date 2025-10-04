import express from 'express';
import cors from 'cors';
import { PrismaClient, AppointmentStatus } from '@prisma/client';

const app = express();
const prisma = new PrismaClient();

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// --- Static admin page
app.use('/admin', express.static('public/admin', { extensions: ['html'] }));

// --- Health root
app.get('/', (_req, res) => {
  res.type('text/plain').send([
    'Онлайн‑запись',
    'Сервер: Express + Prisma',
    '',
    'GET /api/services',
    'POST /api/appointments',
    'GET /admin/api/services',
    'POST /admin/api/services',
    'PUT /admin/api/services/:id',
    'DELETE /admin/api/services/:id',
  ].join('\n'));
});

// ---------- PUBLIC API ----------

app.get('/api/services', async (_req, res) => {
  const list = await prisma.service.findMany({
    orderBy: { createdAt: 'asc' },
    select: { id: true, name: true, durationMin: true, priceCents: true }
  });
  res.json(list);
});

type AppointmentBody = {
  serviceId: string;
  startAtISO: string;
  durationMin?: number;
  client?: { tgUserId?: string };
  staffId?: string;
};

app.post('/api/appointments', async (req, res) => {
  try {
    const { serviceId, startAtISO, durationMin, client, staffId } = req.body as AppointmentBody;
    if (!serviceId || !startAtISO) {
      return res.status(400).json({ error: 'serviceId and startAtISO are required' });
    }

    const service = await prisma.service.findUnique({ where: { id: serviceId } });
    if (!service) return res.status(404).json({ error: 'Service not found' });

    const startAt = new Date(startAtISO);
    const dur = durationMin ?? service.durationMin;
    const endAt = new Date(startAt.getTime() + dur * 60 * 1000);

    // resolve client by tgUserId if provided
    let clientConnect: { connect: { id: string } } | undefined = undefined;
    if (client?.tgUserId) {
      const existing = await prisma.client.findFirst({ where: { tgUserId: client.tgUserId } });
      const ensured = existing ?? await prisma.client.create({ data: { tgUserId: client.tgUserId } });
      clientConnect = { connect: { id: ensured.id } };
    }

    const appointment = await prisma.appointment.create({
      data: {
        startAt,
        endAt,
        status: AppointmentStatus.CREATED,
        service: { connect: { id: service.id } },
        ...(clientConnect ? { client: clientConnect } : {}),
        ...(staffId ? { staff: { connect: { id: staffId } } } : {})
      },
      include: {
        service: true,
        client: true,
        staff: true,
      }
    });

    res.status(201).json(appointment);
  } catch (e:any) {
    console.error(e);
    res.status(500).json({ error: 'Failed to create appointment', detail: String(e?.message || e) });
  }
});

// ---------- ADMIN API (very light) ----------
function checkAdmin(req: express.Request, res: express.Response): boolean {
  const required = process.env.ADMIN_KEY;
  if (!required) return true;
  const actual = req.header('X-Admin-Key') || '';
  if (actual !== required) {
    res.status(401).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
}

app.get('/admin/api/services', async (req, res) => {
  if (!checkAdmin(req, res)) return;
  const list = await prisma.service.findMany({
    orderBy: { createdAt: 'asc' },
    select: { id: true, name: true, durationMin: true, priceCents: true }
  });
  res.json(list);
});

app.post('/admin/api/services', async (req, res) => {
  if (!checkAdmin(req, res)) return;
  const { name, durationMin, priceCents } = req.body || {};
  if (!name || !durationMin || !priceCents) {
    return res.status(400).json({ error: 'name, durationMin, priceCents are required' });
  }
  const created = await prisma.service.create({ data: { name, durationMin: Number(durationMin), priceCents: Number(priceCents) } });
  res.status(201).json(created);
});

app.put('/admin/api/services/:id', async (req, res) => {
  if (!checkAdmin(req, res)) return;
  const { id } = req.params;
  const { name, durationMin, priceCents } = req.body || {};
  const updated = await prisma.service.update({
    where: { id },
    data: {
      ...(name ? { name } : {}),
      ...(durationMin ? { durationMin: Number(durationMin) } : {}),
      ...(priceCents ? { priceCents: Number(priceCents) } : {}),
    }
  });
  res.json(updated);
});

app.delete('/admin/api/services/:id', async (req, res) => {
  if (!checkAdmin(req, res)) return;
  const { id } = req.params;
  await prisma.service.delete({ where: { id } });
  res.status(204).end();
});

const PORT = Number(process.env.PORT || 3000);
app.listen(PORT, () => {
  console.log('Server started on :' + PORT);
});