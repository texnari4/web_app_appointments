import express, { Request, Response, NextFunction } from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { nanoid } from 'nanoid';
import { readDb, writeDb, type Master } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT || 8080);

// basic logging
app.use((req, _res, next) => {
  console.info(`[req] ${req.method} ${req.url}`);
  next();
});

app.use(express.json());
app.use('/public', express.static(path.join(__dirname, '../public')));

// health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// admin UI
app.get(['/admin', '/admin/'], (_req, res) => {
  res.sendFile(path.join(__dirname, '../public/admin/index.html'));
});

// API: Masters
app.get('/public/api/masters', async (_req, res, next) => {
  try {
    const db = await readDb();
    res.json({ items: db.masters });
  } catch (e) { next(e); }
});

app.post('/public/api/masters', async (req, res, next) => {
  try {
    const { name, phone, avatarUrl } = req.body ?? {};
    if (!name || !phone) {
      return res.status(400).json({ error: 'name and phone are required' });
    }
    const now = new Date().toISOString();
    const item: Master = {
      id: nanoid(),
      name: String(name),
      phone: String(phone),
      avatarUrl: String(avatarUrl || ''),
      isActive: true,
      createdAt: now,
      updatedAt: now
    };
    const db = await readDb();
    db.masters.push(item);
    await writeDb(db);
    res.status(201).json({ ok: true, item });
  } catch (e) { next(e); }
});

app.use((req, res, _next) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

// error handler with JSON body to avoid admin-side parse errors
app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  console.error('[error]', err);
  const message = err instanceof Error ? err.message : 'Internal Error';
  res.status(500).json({ error: message });
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});