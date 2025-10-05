
import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pino from 'pino';
import { fileURLToPath } from 'node:url';
import { addMaster, deleteMaster, listMasters } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = Number(process.env.PORT || 8080);
const DATA_DIR = process.env.DATA_DIR || '/app/data';

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });

const app = express();
app.use(cors());
app.use(express.json());
app.use((req, _res, next) => {
  logger.info({ method: req.method, url: req.url }, 'HTTP');
  next();
});

// health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// static admin
app.use('/admin', express.static(path.join(__dirname, '../public/admin')));
app.use('/public', express.static(path.join(__dirname, '../public')));

// API (public namespace to keep existing links)
app.get('/public/api/masters', async (_req, res) => {
  try {
    const items = await listMasters();
    res.json({ items });
  } catch (e) {
    logger.error({ err: e }, 'list masters failed');
    res.status(500).json({ error: 'failed_to_list' });
  }
});

app.post('/public/api/masters', async (req, res) => {
  try {
    const { name, phone, avatarUrl, isActive } = req.body || {};
    if (!name || !phone) {
      return res.status(400).json({ error: 'name_and_phone_required' });
    }
    const item = await addMaster({ name, phone, avatarUrl, isActive });
    res.status(201).json(item);
  } catch (e) {
    logger.error({ err: e }, 'add master failed');
    res.status(500).json({ error: 'failed_to_add' });
  }
});

app.delete('/public/api/masters/:id', async (req, res) => {
  try {
    const ok = await deleteMaster(req.params.id);
    if (!ok) return res.status(404).json({ error: 'not_found' });
    res.json({ ok: true });
  } catch (e) {
    logger.error({ err: e }, 'delete master failed');
    res.status(500).json({ error: 'failed_to_delete' });
  }
});

app.get('/', (_req, res) => {
  res.status(404).send('Not found');
});

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT} (DATA_DIR=${DATA_DIR})`);
});
