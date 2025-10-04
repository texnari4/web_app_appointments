import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import path from 'node:path';

import { prisma } from './prisma';
import { masterCreateSchema } from './validators';

const app = express();
const logger = pino({ level: process.env.LOG_LEVEL || 'info' });

app.use(express.json());
app.use(cors());
app.use(pinoHttp({ logger }));

// Static files (admin UI)
const publicDir = path.resolve(process.cwd(), 'public');
app.use(express.static(publicDir));

// Health
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString(), version: '2.3.4' });
});

// Masters API
app.get('/api/masters', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const masters = await prisma.master.findMany({ orderBy: { createdAt: 'desc' } });
    res.json({ ok: true, data: masters });
  } catch (e) {
    next(e);
  }
});

app.post('/api/masters', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = masterCreateSchema.parse(req.body);
    const created = await prisma.master.create({ data: { name: parsed.name } });
    res.status(201).json({ ok: true, data: created });
  } catch (e) {
    next(e);
  }
});

// Serve admin page at /admin
app.get('/admin', (_req: Request, res: Response) => {
  res.sendFile(path.join(publicDir, 'admin', 'index.html'));
});

// 404 handler
app.use((_req: Request, res: Response) => {
  res.status(404).json({ ok: false, error: 'Not Found' });
});

// Error handler
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  const status = err?.statusCode || err?.status || 500;
  res.status(status).json({ ok: false, error: err?.message || 'Internal Server Error' });
});

const port = Number(process.env.PORT) || 8080;
app.listen(port, () => {
  logger.info(`Server started on :${port}`);
});
