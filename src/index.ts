import express, { Request, Response } from 'express';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import path from 'path';
import { fileURLToPath } from 'url';

import { prisma, ensureDbConnection } from './prisma';
import { MasterCreateSchema, ServiceCreateSchema, AppointmentCreateSchema } from './validators';

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const httpLogger = pinoHttp({ logger });

const app = express();
app.use(express.json());
app.use(cors());
app.use(httpLogger);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = parseInt(process.env.PORT || '8080', 10);

app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Serve admin static UI
app.use('/admin', express.static(path.resolve(__dirname, '..', 'public', 'admin')));

// Root endpoint
app.get('/', (_req, res) => {
  res.status(200).send('Web App Appointments API');
});

// Masters
app.get('/api/masters', async (_req, res) => {
  const masters = await prisma.master.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(masters);
});

app.post('/api/masters', async (req, res) => {
  const parse = MasterCreateSchema.safeParse(req.body);
  if (!parse.success) return res.status(400).json({ error: parse.error.flatten() });
  const master = await prisma.master.create({ data: parse.data });
  res.status(201).json(master);
});

// Services
app.get('/api/services', async (_req, res) => {
  const services = await prisma.service.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(services);
});

app.post('/api/services', async (req, res) => {
  const parse = ServiceCreateSchema.safeParse(req.body);
  if (!parse.success) return res.status(400).json({ error: parse.error.flatten() });
  const service = await prisma.service.create({ data: parse.data });
  res.status(201).json(service);
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
  const parse = AppointmentCreateSchema.safeParse(req.body);
  if (!parse.success) return res.status(400).json({ error: parse.error.flatten() });

  // simple overlap check for the same master
  const overlap = await prisma.appointment.findFirst({
    where: {
      masterId: parse.data.masterId,
      OR: [
        { startsAt: { lt: parse.data.endsAt }, endsAt: { gt: parse.data.startsAt } },
      ],
    },
  });
  if (overlap) return res.status(409).json({ error: 'Time slot overlaps with existing appointment' });

  const appt = await prisma.appointment.create({ data: parse.data });
  res.status(201).json(appt);
});

// Not found
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

async function main() {
  try {
    await ensureDbConnection();
    app.listen(PORT, () => logger.info({ port: PORT }, 'Server started'));
  } catch (e) {
    logger.error(e, 'Fatal during startup');
    process.exit(1);
  }
}

main();