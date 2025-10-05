import express, { Request, Response } from 'express';
import path from 'node:path';
import cors from 'cors';
import { fileURLToPath } from 'node:url';
import { listMasters, createMaster, listAppointments, createAppointment } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT || 8080);

// Simple logger middleware
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

app.use(cors());
app.use(express.json());
app.use('/public', express.static(path.join(__dirname, '..', 'public'), { extensions: ['html'] }));

// Health
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Admin (serve UI)
app.get(['/admin', '/admin/'], (_req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'admin', 'index.html'));
});

// API: Masters
app.get(['/public/api/masters', '/api/masters'], async (_req: Request, res: Response) => {
  try {
    const items = await listMasters();
    res.json({ items });
  } catch (e: any) {
    res.status(500).json({ error: e?.message || 'Internal error' });
  }
});

app.post(['/public/api/masters', '/api/masters'], async (req: Request, res: Response) => {
  try {
    const { name, phone, avatarUrl, isActive } = req.body || {};
    if (!name || !phone) return res.status(400).json({ error: 'name and phone are required' });
    const item = await createMaster({ name, phone, avatarUrl, isActive });
    res.json({ ok: true, item });
  } catch (e: any) {
    res.status(500).json({ error: e?.message || 'Internal error' });
  }
});

// API: Appointments
app.get(['/public/api/appointments', '/api/appointments'], async (req: Request, res: Response) => {
  try {
    const items = await listAppointments({
      from: req.query.from as string | undefined,
      to: req.query.to as string | undefined,
      masterId: req.query.masterId as string | undefined
    });
    res.json({ items });
  } catch (e: any) {
    res.status(500).json({ error: e?.message || 'Internal error' });
  }
});

app.post(['/public/api/appointments', '/api/appointments'], async (req: Request, res: Response) => {
  try {
    const { masterId, clientName, clientPhone, startsAt, endsAt } = req.body || {};
    if (!masterId || !clientName || !clientPhone || !startsAt || !endsAt) {
      return res.status(400).json({ error: 'masterId, clientName, clientPhone, startsAt, endsAt are required' });
    }
    const item = await createAppointment({ masterId, clientName, clientPhone, startsAt, endsAt });
    res.json({ ok: true, item });
  } catch (e: any) {
    res.status(500).json({ error: e?.message || 'Internal error' });
  }
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});