import express, { Request, Response } from 'express';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { PrismaClient } from '@prisma/client';

import { serviceSchema, masterSchema } from './validators';

const prisma = new PrismaClient();
const logger = pino();
const app = express();

app.use(cors());
app.use(express.json());
app.use(pinoHttp({ logger }));

// Health endpoint
app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

// Services endpoints
app.get('/services', async (_req: Request, res: Response) => {
  const services = await prisma.service.findMany({ include: { master: true } });
  res.json(services);
});

app.post('/services', async (req: Request, res: Response) => {
  const parsed = serviceSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.errors });
    return;
  }
  const { name, price, durationMin, masterId } = parsed.data;
  const service = await prisma.service.create({ data: { name, price, durationMin, masterId } });
  res.status(201).json(service);
});

// Masters endpoints
app.get('/masters', async (_req: Request, res: Response) => {
  const masters = await prisma.master.findMany({ include: { services: true } });
  res.json(masters);
});

app.post('/masters', async (req: Request, res: Response) => {
  const parsed = masterSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.errors });
    return;
  }
  const { name, phone, email } = parsed.data;
  const master = await prisma.master.create({ data: { name, phone, email } });
  res.status(201).json(master);
});

const port = process.env.PORT ?? 8080;
app.listen(Number(port), () => {
  logger.info({ msg: `Server started on :${port}` });
});
