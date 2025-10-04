import express from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';
import { prisma } from './prisma';
import { masterCreateSchema } from './validators';

const app = express();
const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const VERSION = '2.3.5';

// Middlewares
app.use(cors());
app.use(express.json());
app.use(
  pinoHttp({
    transport: process.env.NODE_ENV !== 'production' ? { target: 'pino-pretty' } : undefined,
  })
);

// Static admin
app.use('/admin', express.static('public/admin'));
app.use('/', express.static('public'));

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString(), version: VERSION });
});

// Masters API
app.get('/api/masters', async (_req, res) => {
  try {
    const masters = await prisma.master.findMany({ orderBy: { createdAt: 'desc' } });
    res.json({ ok: true, data: masters });
  } catch (e) {
    req.log?.error({ err: e }, 'Failed to list masters');
    res.status(500).json({ ok: false, error: 'INTERNAL_ERROR' });
  }
});

app.post('/api/masters', async (req, res) => {
  try {
    const parsed = masterCreateSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ ok: false, error: 'VALIDATION_ERROR', issues: parsed.error.issues });
    }
    const master = await prisma.master.create({ data: { name: parsed.data.name } });
    res.status(201).json({ ok: true, data: master });
  } catch (e) {
    req.log?.error({ err: e }, 'Failed to create master');
    res.status(500).json({ ok: false, error: 'INTERNAL_ERROR' });
  }
});

// 404
app.use((_req, res) => res.status(404).json({ ok: false, error: 'NOT_FOUND' }));

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});