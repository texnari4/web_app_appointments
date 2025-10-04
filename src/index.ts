import express from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import prisma from './prisma.js';
import { MasterCreateSchema } from './validators.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = Number(process.env.PORT ?? 8080);

app.use(pinoHttp());
app.use(cors());
app.use(express.json()); // ✅ важно для POST JSON
app.use(express.urlencoded({ extended: true }));

// Статика (включая админку)
app.use('/public', express.static(path.join(__dirname, '..', 'public')));

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Админка (роут чтобы было красиво /admin)
app.get('/admin', (_req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'admin', 'index.html'));
});

// --- Masters API ---
app.get('/api/masters', async (_req, res, next) => {
  try {
    const list = await prisma.master.findMany({ orderBy: { createdAt: 'desc' } });
    res.json(list);
  } catch (e) { next(e); }
});

app.post('/api/masters', async (req, res, next) => {
  try {
    const parsed = MasterCreateSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() });
    }
    const created = await prisma.master.create({
      data: { name: parsed.data.name }
    });
    res.status(201).json(created);
  } catch (e:any) {
    if (e?.code === 'P2002') {
      return res.status(409).json({ error: 'DUPLICATE', field: 'name' });
    }
    next(e);
  }
});

// Корень - редирект на /admin
app.get('/', (_req, res) => {
  res.redirect('/admin');
});

// Ошибки
// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  req.log?.error({ err }, 'Unhandled error');
  res.status(500).json({ error: 'INTERNAL_ERROR' });
});

app.listen(port, () => {
  console.log(`Server started on :${port}`);
});
