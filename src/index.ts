import express, { Request, Response } from 'express';
import path from 'node:path';
import cors from 'cors';
import pinoHttp from 'pino-http';
import { fileURLToPath } from 'node:url';
import { addMaster, listMasters, addAppointment, listAppointments } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(cors());
app.use(express.json());
app.use(pinoHttp());

const PORT = Number(process.env.PORT || 8080);
const DATA_DIR = process.env.DATA_DIR || '/app/data';

// health
app.get('/health', (_req: Request, res: Response) => res.json({ ok: true, ts: new Date().toISOString() }));

// static admin
app.use('/admin', express.static(path.join(__dirname, '..', 'public', 'admin')));

// masters API (public)
app.get('/public/api/masters', async (_req: Request, res: Response) => {
  const items = await listMasters();
  res.json({ items });
});

app.post('/public/api/masters', async (req: Request, res: Response) => {
  try {
    const { name, phone, avatarUrl } = req.body ?? {};
    const m = await addMaster({ name, phone, avatarUrl, isActive: true });
    res.status(201).json(m);
  } catch (e) {
    res.status(400).json({ error: 'CREATE_FAILED' });
  }
});

// appointments API (public)
app.get('/public/api/appointments', async (req: Request, res: Response) => {
  const { masterId, from, to } = req.query as { masterId?: string; from?: string; to?: string };
  const items = await listAppointments({ masterId, from, to });
  res.json({ items });
});

app.post('/public/api/appointments', async (req: Request, res: Response) => {
  try {
    const { masterId, clientName, clientPhone, start, end, note } = req.body ?? {};
    const created = await addAppointment({
      masterId, clientName, clientPhone, start, end, note, status: 'scheduled'
    });
    res.status(201).json(created);
  } catch (e: any) {
    if (e && e.message === 'TIME_CONFLICT') {
      res.status(409).json({ error: 'TIME_CONFLICT' });
    } else {
      res.status(400).json({ error: 'CREATE_FAILED' });
    }
  }
});

// serve index redirect
app.get('/', (_req: Request, res: Response) => res.redirect('/admin/'));

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server started on :${PORT} (DATA_DIR=${DATA_DIR})`);
});