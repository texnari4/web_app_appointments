import express, { Request, Response } from 'express';
import cors from 'cors';
import { PrismaClient } from '@prisma/client';

const app = express();
const prisma = new PrismaClient();

app.use(cors());
app.use(express.json());

app.get('/', (_req: Request, res: Response) => {
  res.type('text/plain').send([
    'Онлайн‑запись',
    'Сервер: Express + Prisma',
    '',
    'GET  /api/services',
    'POST /api/appointments',
    'GET  /admin/api/services',
    'POST /admin/api/services',
    'PUT  /admin/api/services/:id',
    'DELETE /admin/api/services/:id',
  ].join('\n'));
});

// Public API — list services
app.get('/api/services', async (_req: Request, res: Response) => {
  const items = await prisma.service.findMany({
    orderBy: { createdAt: 'desc' },
  });
  res.json(items);
});

// Public API — create appointment
app.post('/api/appointments', async (req: Request, res: Response) => {
  try {
    const { serviceId, time, tgUserId, name, phone } = req.body ?? {};

    if (!serviceId || !time) {
      return res.status(400).json({ error: 'serviceId and time are required' });
    }

    // upsert client if tgUserId provided
    let clientId: string | undefined = undefined;
    if (tgUserId) {
      const client = await prisma.client.upsert({
        where: { tgUserId },
        update: { name, phone },
        create: { tgUserId, name, phone },
      });
      clientId = client.id;
    }

    const created = await prisma.appointment.create({
      data: {
        serviceId,
        clientId,
        time: new Date(time),
        status: 'booked',
      },
      include: { service: true, client: true },
    });

    res.status(201).json(created);
  } catch (e: any) {
    console.error('POST /api/appointments error', e);
    res.status(500).json({ error: 'Internal error', detail: e?.message });
  }
});

// Admin API — list services
app.get('/admin/api/services', async (_req: Request, res: Response) => {
  const items = await prisma.service.findMany({
    orderBy: { createdAt: 'desc' },
  });
  res.json(items);
});

// Admin API — create service
app.post('/admin/api/services', async (req: Request, res: Response) => {
  const { name, description, price, duration } = req.body ?? {};
  if (!name) return res.status(400).json({ error: 'name is required' });
  const created = await prisma.service.create({
    data: {
      name,
      description,
      price: price != null ? Number(price) : undefined,
      duration: duration != null ? Number(duration) : undefined,
    },
  });
  res.status(201).json(created);
});

// Admin API — update service
app.put('/admin/api/services/:id', async (req: Request, res: Response) => {
  const { id } = req.params;
  const { name, description, price, duration } = req.body ?? {};
  const updated = await prisma.service.update({
    where: { id },
    data: {
      name,
      description,
      price: price != null ? Number(price) : undefined,
      duration: duration != null ? Number(duration) : undefined,
    },
  });
  res.json(updated);
});

// Admin API — delete service
app.delete('/admin/api/services/:id', async (req: Request, res: Response) => {
  const { id } = req.params;
  await prisma.service.delete({ where: { id } });
  res.status(204).send();
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`Server started on :${port}`);
});