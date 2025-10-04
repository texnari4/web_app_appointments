import express from 'express';
import pino from 'pino';
import pinoHttp from 'pino-http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMaster, listMasters, deleteMaster } from './storage.js';

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const httpLogger = pinoHttp({ logger });

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(express.json({ limit: '1mb' }));
app.use(httpLogger);

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Static admin
const adminDir = path.join(__dirname, '..', 'public', 'admin');
app.use('/admin', express.static(adminDir, { extensions: ['html'] }));

// API: public list
app.get('/public/api/masters', async (_req, res, next) => {
  try {
    const masters = await listMasters();
    res.json({ ok: true, data: masters });
  } catch (err) { next(err); }
});

// API: create master (admin)
app.post('/admin/api/masters', async (req, res, next) => {
  try {
    const { name, phone, about, avatarUrl } = req.body ?? {};
    if (!name || typeof name !== 'string') {
      res.status(400).json({ ok: false, error: 'NAME_REQUIRED' });
      return;
    }
    const master = await createMaster({ name, phone, about, avatarUrl });
    res.status(201).json({ ok: true, data: master });
  } catch (err) { next(err); }
});

// API: delete master (admin)
app.delete('/admin/api/masters/:id', async (req, res, next) => {
  try {
    const { id } = req.params;
    const ok = await deleteMaster(id);
    res.json({ ok });
  } catch (err) { next(err); }
});

// Root - explicit 404 JSON for bots/Telegram
app.all('/', (_req, res) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

// Fallback 404
app.use((_req, res) => res.status(404).json({ error: 'NOT_FOUND' }));

// Error handler
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logger.error({ err }, 'unhandled_error');
  res.status(500).json({ ok: false, error: 'INTERNAL_ERROR' });
});

const PORT = Number(process.env.PORT || 8080);
app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
