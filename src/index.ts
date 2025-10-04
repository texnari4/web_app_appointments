import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import { PrismaClient, AppointmentStatus } from '@prisma/client';

const app = express();
const prisma = new PrismaClient();

app.use(cors());
app.use(express.json());

// Healthcheck
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, env: process.env.NODE_ENV, time: new Date().toISOString() });
});

// Services CRUD (Admin MVP)
app.get('/api/services', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const items = await prisma.service.findMany({ orderBy: { name: 'asc' } });
    res.json(items);
  } catch (e) { next(e); }
});

app.post('/api/services', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { name, description, price, durationMinutes } = req.body;
    const created = await prisma.service.create({
      data: { name, description, price: Number(price) || 0, durationMinutes: Number(durationMinutes) || 30 }
    });
    res.status(201).json(created);
  } catch (e) { next(e); }
});

app.put('/api/services/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { name, description, price, durationMinutes } = req.body;
    const updated = await prisma.service.update({
      where: { id },
      data: { name, description, price: Number(price), durationMinutes: Number(durationMinutes) }
    });
    res.json(updated);
  } catch (e) { next(e); }
});

app.delete('/api/services/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    await prisma.service.delete({ where: { id } });
    res.status(204).send();
  } catch (e) { next(e); }
});

// Create Appointment (Client MVP)
app.post('/api/appointments', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { clientName, clientPhone, masterId, serviceId, startsAt } = req.body;
    const svc = await prisma.service.findUnique({ where: { id: serviceId } });
    if (!svc) return res.status(400).json({ error: 'Service not found' });

    const start = new Date(startsAt);
    const end = new Date(start.getTime() + (svc.durationMinutes || 30) * 60000);

    // Ensure client exists by name+phone (not unique in DB, so findFirst then create)
    let client = await prisma.client.findFirst({ where: { name: clientName, phone: clientPhone } });
    if (!client) {
      client = await prisma.client.create({ data: { name: clientName, phone: clientPhone ?? null } });
    }

    const appt = await prisma.appointment.create({
      data: {
        clientId: client.id,
        masterId,
        serviceId,
        startsAt: start,
        endsAt: end,
        status: AppointmentStatus.SCHEDULED
      },
      include: { client: true, master: true, service: true }
    });

    res.status(201).json(appt);
  } catch (e) { next(e); }
});

// Basic error handler
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  console.error(err);
  res.status(500).json({ error: 'Internal Server Error', detail: String(err?.message || err) });
});

const port = Number(process.env.PORT) || 8080;
app.listen(port, () => {
  console.log(`Server started on :${port}`);
});