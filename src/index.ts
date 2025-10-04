import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';
import path from 'path';

import { prisma } from './prisma';
import { masterCreateSchema } from './validators';

const app = express();
const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;

// Middlewares
app.use(cors());
app.use(express.json());
app.use(
  pinoHttp({
    autoLogging: true,
  })
);

// Health
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, version: '2.3.6', ts: new Date().toISOString() });
});

// Static
app.use('/public', express.static(path.join(__dirname, '..', 'public')));

// Admin page
app.get('/admin', (_req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'admin', 'index.html'));
});

// API — masters
app.get('/api/masters', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const items = await prisma.master.findMany({
      orderBy: { createdAt: 'desc' },
    });
    res.json(items);
  } catch (err) {
    next(err);
  }
});

app.post('/api/masters', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const input = masterCreateSchema.parse(req.body);
    const created = await prisma.master.create({
      data: { name: input.name },
    });
    res.status(201).json(created);
  } catch (err) {
    next(err);
  }
});

// Error handler (keep parameter names consistent with usage)
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  const status = (typeof err?.statusCode === 'number' && err.statusCode) || 400;
  const message = (typeof err?.message === 'string' && err.message) || 'Bad Request';
  res.status(status).json({ ok: false, error: message });
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server started on :${PORT}`);
});