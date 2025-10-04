
import express from 'express';
import pinoHttp from 'pino-http';
import path from 'path';
import { fileURLToPath } from 'url';
import { storage } from './storage.js';
import { masterCreateSchema, MasterCreateInput } from './validators.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT || 8080);
const DATA_DIR = process.env.DATA_DIR || '/app/data';

app.use(express.json());
app.use(pinoHttp());
app.use('/public', express.static(path.join(__dirname, '..', 'public')));

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Admin static
app.get('/admin/', (_req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'admin', 'index.html'));
});

// Admin API
app.get('/admin/api/masters', async (_req, res) => {
  const list = await storage.masters.all();
  res.json(list);
});

app.post('/admin/api/masters', async (req, res) => {
  try {
    const dto = masterCreateSchema.parse(req.body) as MasterCreateInput;
    const created = await storage.masters.create({
      name: dto.name.trim(),
      phone: dto.phone ?? null,
      about: dto.about ?? null,
      avatarUrl: dto.avatarUrl ?? null
    });
    res.status(201).json(created);
  } catch (e: any) {
    req.log?.error?.(e);
    res.status(400).json({ error: e?.message || 'BAD_REQUEST' });
  }
});

app.delete('/admin/api/masters/:id', async (req, res) => {
  const ok = await storage.masters.remove(req.params.id);
  res.json({ ok });
});

// Root -> serve index.html
app.get('/', (_req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

// 404 JSON for unknown API
app.use((req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT} (DATA_DIR=${DATA_DIR})`);
});
