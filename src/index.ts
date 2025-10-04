import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import path from 'path';
import pinoHttp from 'pino-http';
import { masterCreateSchema } from './validators';
import { prisma } from './prisma';

const app = express();

// Middlewares
app.use(cors());
app.use(express.json());
app.use(pinoHttp());

// Health
app.get('/health', (_req: Request, res: Response) => {
  res.json({
    ok: true,
    version: process.env.APP_VERSION ?? '2.3.6',
    ts: new Date().toISOString()
  });
});

// Static
app.use('/public', express.static(path.join(__dirname, '..', 'public')));

// Admin page
app.get('/admin', (_req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'admin', 'index.html'));
});

// API: masters
app.get('/api/masters', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const items = await prisma.master.findMany({
      orderBy: { createdAt: 'desc' }
    });
    res.json({ data: items });
  } catch (err) {
    next(err);
  }
});

app.post('/api/masters', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = masterCreateSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({
        error: 'ValidationError',
        details: parsed.error.flatten()
      });
    }
    const created = await prisma.master.create({
      data: {
        name: parsed.data.name
      }
    });
    res.status(201).json({ data: created });
  } catch (err) {
    next(err);
  }
});

// 404
app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: 'Not Found' });
});

// Error handler (fix: use the same parameter name as referenced inside)
app.use((err: any, req: Request, res: Response, _next: NextFunction) => {
  // pino-http attaches req.log
  try {
    // @ts-ignore
    req.log?.error?.({ err }, 'Unhandled error');
  } catch {}
  res.status(500).json({ error: 'Internal Server Error' });
});

const PORT = Number(process.env.PORT || 8080);
app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server started on :${PORT}`);
});
