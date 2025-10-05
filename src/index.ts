import express from 'express';
import cors from 'cors';
import pino from 'pino';
import path from 'node:path';
import { ensureDb, listMasters, createMaster } from './db.js';

const app = express();
const logger = pino();

app.use(cors());
app.use(express.json());

// Simple request logger (instead of pino-http)
app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    logger.info({ method: req.method, url: req.originalUrl, status: res.statusCode, ms: Date.now() - started });
  });
  next();
});

const PORT = Number(process.env.PORT || 8080);

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Static admin (if you serve it)
app.use('/admin', express.static(path.join(process.cwd(), 'public', 'admin')));

// API examples
app.get(['/api/masters', '/public/api/masters'], async (_req, res) => {
  const items = await listMasters();
  res.json({ items });
});

app.post(['/api/masters', '/public/api/masters'], async (req, res) => {
  try {
    const master = await createMaster(req.body || {});
    res.status(201).json(master);
  } catch (e: any) {
    res.status(400).json({ error: e?.message || 'Bad Request' });
  }
});

// Boot
await ensureDb();
app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});