import express from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';
import path from 'node:path';
import { fileURLToPath } from 'node:url'; // safe for NodeNext or CJS transpile
import { prisma } from './prisma';
import { MasterCreateSchema } from './validators';

// Resolve project root in both ESM/CJS scenarios
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = process.cwd();

const app = express();

// middleware
app.use(cors());
app.use(express.json());
app.use(pinoHttp()); // correct usage: default import returns a middleware function

// health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// static
app.use('/public', express.static(path.join(ROOT, 'public')));

// simple admin: serve index
app.get(['/admin', '/admin/'], (_req, res) => {
  res.sendFile(path.join(ROOT, 'public', 'admin', 'index.html'));
});

// redirect root -> /admin
app.get('/', (_req, res) => res.redirect('/admin'));

// API: masters
app.get('/api/masters', async (_req, res) => {
  try {
    const masters = await prisma.master.findMany({
      orderBy: { createdAt: 'desc' },
    });
    res.json(masters);
  } catch (err) {
    req.log?.error({ err }, 'Failed to list masters');
    res.status(500).json({ error: 'INTERNAL' });
  }
});

app.post('/api/masters', async (req, res) => {
  try {
    const parsed = MasterCreateSchema.parse(req.body);
    const created = await prisma.master.create({
      data: { name: parsed.name },
    });
    res.status(201).json(created);
  } catch (err: any) {
    if (err?.name === 'ZodError') {
      return res.status(400).json({ error: 'VALIDATION', issues: err.issues });
    }
    if (err?.code === 'P2002') {
      return res.status(409).json({ error: 'DUPLICATE' });
    }
    req.log?.error({ err }, 'Failed to create master');
    res.status(500).json({ error: 'INTERNAL' });
  }
});

const port = Number(process.env.PORT) || 8080;
app.listen(port, () => {
  // Use console as a fallback logger in case pino is not configured to pretty-print
  console.log(`Server started on :${port}`);
});

export default app;
