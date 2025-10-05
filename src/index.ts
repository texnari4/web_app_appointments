import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pinoHttp from 'pino-http';
import { fileURLToPath } from 'node:url';

import { listMasters, createMaster, updateMaster, deleteMaster } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT || 8080);

app.use(pinoHttp());
app.use(cors());
app.use(express.json({ limit: '1mb' }));

// health
app.get('/health', (_req, res) => { res.json({ ok: true, ts: new Date().toISOString() }); });

// static
app.use('/public', express.static(path.join(__dirname, '../public')));

// admin html
app.get(['/admin', '/admin/'], (_req, res) => {
  res.sendFile(path.join(__dirname, '../public/admin/index.html'));
});
app.get('/admin/styles.css', (_req, res) => {
  res.sendFile(path.join(__dirname, '../public/admin/styles.css'));
});
app.get('/admin/app.js', (_req, res) => {
  res.sendFile(path.join(__dirname, '../public/admin/app.js'));
});

// API: masters
app.get('/public/api/masters', async (_req, res) => {
  const items = await listMasters();
  res.json({ items });
});
app.post('/public/api/masters', async (req, res) => {
  try {
    const item = await createMaster(req.body || {});
    res.json({ item });
  } catch (e) {
    res.status(400).json({ error: String(e) });
  }
});
app.put('/public/api/masters/:id', async (req, res) => {
  const id = req.params.id;
  const item = await updateMaster(id, req.body || {});
  if(!item) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ item });
});
app.delete('/public/api/masters/:id', async (req, res) => {
  const id = req.params.id;
  await deleteMaster(id);
  res.json({ ok: true });
});

// root 404
app.get('/', (_req, res)=> res.status(404).json({ error: 'NOT_FOUND' }));

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
