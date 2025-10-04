import express from 'express';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import path from 'path';
import { prisma, ensureDb } from './prisma';
import { masterCreateSchema } from './validators';

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
});

const app = express();
app.use(cors());
app.use(express.json());
app.use(pinoHttp({ logger }));

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Static files
const publicDir = path.join(process.cwd(), 'public');
app.use('/public', express.static(publicDir));

// Admin panel
app.get('/admin', (_req, res) => {
  res.sendFile(path.join(publicDir, 'admin', 'index.html'));
});
app.get('/admin/', (_req, res) => {
  res.sendFile(path.join(publicDir, 'admin', 'index.html'));
});

// API: Masters
app.get('/api/masters', async (_req, res, next) => {
  try {
    const masters = await prisma.master.findMany({
      orderBy: { id: 'desc' },
    });
    res.json({ data: masters });
  } catch (e) {
    next(e);
  }
});

app.post('/api/masters', async (req, res, next) => {
  try {
    const parsed = masterCreateSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() });
    }
    const created = await prisma.master.create({ data: parsed.data });
    res.status(201).json({ data: created });
  } catch (e) {
    next(e);
  }
});

// Make root redirect to /admin for now (so Telegram "open" sees something)
app.get('/', (_req, res) => {
  res.redirect('/admin');
});

// 404 (JSON for API; HTML for others)
app.use((req, res, _next) => {
  if (req.path.startsWith('/api/')) {
    res.status(404).json({ error: 'NOT_FOUND' });
  } else {
    res.status(404).sendFile(path.join(publicDir, '404.html'));
  }
});

// Error handler
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  req.log?.error({ err }, 'request error');
  res.status(500).json({ error: 'INTERNAL_ERROR' });
});

async function main() {
  await ensureDb();
  app.listen(PORT, () => {
    logger.info(`Server started on :${PORT}`);
  });
}

main().catch((err) => {
  logger.error(err, 'fatal');
  process.exit(1);
});
