import express, { Request, Response } from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Adjust imports from your db module as needed:
// If your file is src/db.ts compiled to dist/db.js (ESM), use './db.js' at runtime.
import {
  listMasters,
  createMaster,
  updateMaster,
  deleteMaster,
  // optional: listServices, etc...
} from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(cors());
app.use(express.json());
app.use(pinoHttp());

const PORT = Number(process.env.PORT || 8080);

// Health
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Static admin (ensure you copy public at build stage)
app.use('/admin', express.static(path.join(__dirname, '../public/admin'), { extensions: ['html'] }));
app.use('/public', express.static(path.join(__dirname, '../public')));

// Masters API (examples; align with your existing handlers)
app.get(['/api/masters', '/public/api/masters'], async (_req: Request, res: Response) => {
  const items = await listMasters();
  res.json({ items });
});

app.post(['/api/masters', '/public/api/masters'], async (req: Request, res: Response) => {
  try {
    const created = await createMaster(req.body);
    res.status(201).json(created);
  } catch (e: any) {
    req.log?.error({ err: e }, 'createMaster error');
    res.status(400).json({ error: 'CREATE_FAILED', message: e?.message || String(e) });
  }
});

app.put(['/api/masters/:id', '/public/api/masters/:id'], async (req: Request, res: Response) => {
  try {
    const updated = await updateMaster(req.params.id, req.body);
    res.json(updated);
  } catch (e: any) {
    req.log?.error({ err: e }, 'updateMaster error');
    res.status(400).json({ error: 'UPDATE_FAILED', message: e?.message || String(e) });
  }
});

app.delete(['/api/masters/:id', '/public/api/masters/:id'], async (req: Request, res: Response) => {
  try {
    await deleteMaster(req.params.id);
    res.status(204).end();
  } catch (e: any) {
    req.log?.error({ err: e }, 'deleteMaster error');
    res.status(400).json({ error: 'DELETE_FAILED', message: e?.message || String(e) });
  }
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
