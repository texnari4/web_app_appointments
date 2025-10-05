import express, { Request, Response } from 'express';
import path from 'node:path';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { listMasters, createMaster, listAppointments, createAppointment, ensureReady } from './db.js';

const app = express();
const logger = pino({ level: process.env.LOG_LEVEL ?? 'info' });
app.use(pinoHttp({ logger }));

const PORT = Number(process.env.PORT ?? 8080);
const PUBLIC_DIR = path.resolve(process.cwd(), 'public');

app.use(cors());
app.use(express.json());
app.use('/public', express.static(PUBLIC_DIR));

app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// API: Masters
app.get(['/public/api/masters','/api/masters'], async (_req: Request, res: Response) => {
  try {
    const items = await listMasters();
    res.json({ items });
  } catch (e) {
    reqLog(res).error({ err: e }, 'masters.list failed');
    res.status(500).json({ error: 'INTERNAL_ERROR' });
  }
});

app.post(['/public/api/masters','/api/masters'], async (req: Request, res: Response) => {
  try {
    const { name, phone, avatarUrl, isActive } = req.body ?? {};
    if (!name || !phone) return res.status(400).json({ error: 'NAME_AND_PHONE_REQUIRED' });
    const item = await createMaster({ name, phone, avatarUrl: avatarUrl ?? '', isActive: isActive ?? true });
    res.status(201).json(item);
  } catch (e) {
    reqLog(res).error({ err: e }, 'masters.create failed');
    res.status(500).json({ error: 'INTERNAL_ERROR' });
  }
});

// API: Appointments (sprint base)
app.get(['/public/api/appointments','/api/appointments'], async (_req: Request, res: Response) => {
  try {
    const items = await listAppointments();
    res.json({ items });
  } catch (e) {
    reqLog(res).error({ err: e }, 'appointments.list failed');
    res.status(500).json({ error: 'INTERNAL_ERROR' });
  }
});

app.post(['/public/api/appointments','/api/appointments'], async (req: Request, res: Response) => {
  try {
    const { masterId, clientName, phone, from, to, note } = req.body ?? {};
    if (!masterId || !clientName || !phone || !from || !to) return res.status(400).json({ error: 'REQUIRED_FIELDS' });
    const item = await createAppointment({ masterId, clientName, phone, from, to, note });
    res.status(201).json(item);
  } catch (e:any) {
    const msg = e?.message ?? 'INTERNAL_ERROR';
    reqLog(res).error({ err: e }, 'appointments.create failed');
    res.status(msg === 'TIME_CONFLICT' ? 409 : 500).json({ error: msg });
  }
});

// Admin panel
app.get('/', (_req: Request, res: Response) => res.redirect('/admin/'));
app.get('/admin/', (_req: Request, res: Response) => {
  res.sendFile(path.join(PUBLIC_DIR, 'admin', 'index.html'));
});

function reqLog(res: Response) {
  // pino-http attaches logger to res
  // @ts-ignore
  return res.log ?? logger;
}

await ensureReady();
app.listen(PORT, () => logger.info(`Server started on :${PORT}`));
