import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pino from 'pino';
import { db } from './db.js';

const app = express();
const log = pino();

const PORT = Number(process.env.PORT || 8080);

app.use(cors());
app.use(express.json());

// simple request logger
app.use((req, _res, next) => {
  log.info({ method: req.method, url: req.url }, 'request');
  next();
});

// health
app.get(['/health','/public/health'], (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// static admin
const publicDir = path.join(process.cwd(), 'public');
app.use('/public', express.static(publicDir, { fallthrough: true }));
app.get(['/admin','/admin/'], (_req, res) => {
  res.sendFile(path.join(publicDir, 'admin', 'index.html'));
});

// API: masters
app.get(['/api/masters','/public/api/masters'], async (_req, res) => {
  const items = await db.listMasters();
  res.json({ items });
});

app.post(['/api/masters','/public/api/masters'], async (req, res) => {
  try {
    const m = await db.createMaster(req.body || {});
    res.status(201).json(m);
  } catch (e) {
    log.error({ e }, 'create master failed');
    res.status(500).json({ error: 'failed_to_create_master' });
  }
});

// placeholder services (front expects this)
app.get(['/api/services','/public/api/services'], async (_req, res) => {
  // read full DB and return flattened services
  const { serviceGroups } = await (await import('./db.js')).readDb?.() ?? { serviceGroups: [] };
  const items = [];
  for (const g of serviceGroups || []) {
    for (const s of g.services) {
      items.push({ ...s, groupName: g.name });
    }
  }
  res.json({ items });
});

app.listen(PORT, () => {
  log.info(`Server started on :${PORT}`);
});
