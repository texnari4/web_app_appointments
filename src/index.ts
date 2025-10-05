import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pinoHttp from 'pino-http';
import {
  listMasters, addMaster, updateMaster, removeMaster,
  listServices, addService, updateService, removeService,
  listClients, addClient, updateClient, removeClient,
  listAppointments, addAppointment, updateAppointment, removeAppointment,
  report
} from './db.js';

const app = express();
const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';

app.use(cors());
app.use(express.json());
app.use(pinoHttp());

// static
const publicDir = path.join(process.cwd(), 'public');
app.use('/public', express.static(publicDir));

// admin
app.get(['/admin','/admin/'], (_req, res) => {
  res.sendFile(path.join(publicDir, 'admin', 'index.html'));
});

// health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Masters
app.get(['/public/api/masters','/api/masters'], async (_req, res) => {
  const items = await listMasters();
  res.json({ items });
});
app.post(['/public/api/masters','/api/masters'], async (req, res) => {
  try {
    const created = await addMaster(req.body || {});
    res.json(created);
  } catch (e) {
    req.log?.error(e);
    res.status(500).json({ error: 'CREATE_FAILED' });
  }
});
app.put(['/public/api/masters/:id','/api/masters/:id'], async (req, res) => {
  const updated = await updateMaster(req.params.id, req.body || {});
  if (!updated) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json(updated);
});
app.delete(['/public/api/masters/:id','/api/masters/:id'], async (req, res) => {
  const ok = await removeMaster(req.params.id);
  res.json({ ok });
});

// Services
app.get('/public/api/services', async (_req, res) => res.json({ items: await listServices() }));
app.post('/public/api/services', async (req, res) => {
  try {
    const created = await addService(req.body || {});
    res.json(created);
  } catch (e) {
    req.log?.error(e);
    res.status(500).json({ error: 'CREATE_FAILED' });
  }
});
app.put('/public/api/services/:id', async (req, res) => {
  const updated = await updateService(req.params.id, req.body || {});
  if (!updated) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json(updated);
});
app.delete('/public/api/services/:id', async (req, res) => {
  const ok = await removeService(req.params.id);
  res.json({ ok });
});

// Clients
app.get('/public/api/clients', async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q : undefined;
  res.json({ items: await listClients(q) });
});
app.post('/public/api/clients', async (req, res) => {
  try {
    const created = await addClient(req.body || {});
    res.json(created);
  } catch (e) {
    req.log?.error(e);
    res.status(500).json({ error: 'CREATE_FAILED' });
  }
});
app.put('/public/api/clients/:id', async (req, res) => {
  const updated = await updateClient(req.params.id, req.body || {});
  if (!updated) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json(updated);
});
app.delete('/public/api/clients/:id', async (req, res) => {
  const ok = await removeClient(req.params.id);
  res.json({ ok });
});

// Appointments
app.get('/public/api/appointments', async (req, res) => {
  const filters = {
    from: typeof req.query.from === 'string' ? req.query.from : undefined,
    to: typeof req.query.to === 'string' ? req.query.to : undefined,
    masterId: typeof req.query.masterId === 'string' ? req.query.masterId : undefined,
    clientId: typeof req.query.clientId === 'string' ? req.query.clientId : undefined,
    serviceId: typeof req.query.serviceId === 'string' ? req.query.serviceId : undefined,
  };
  res.json({ items: await listAppointments(filters) });
});
app.post('/public/api/appointments', async (req, res) => {
  try {
    const created = await addAppointment(req.body || {});
    res.json(created);
  } catch (e) {
    req.log?.error(e);
    res.status(500).json({ error: 'CREATE_FAILED' });
  }
});
app.put('/public/api/appointments/:id', async (req, res) => {
  const updated = await updateAppointment(req.params.id, req.body || {});
  if (!updated) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json(updated);
});
app.delete('/public/api/appointments/:id', async (req, res) => {
  const ok = await removeAppointment(req.params.id);
  res.json({ ok });
});

// Reports
app.get('/public/api/reports', async (req, res) => {
  const from = typeof req.query.from === 'string' ? req.query.from : new Date(Date.now()-30*864e5).toISOString();
  const to = typeof req.query.to === 'string' ? req.query.to : new Date().toISOString();
  const data = await report(from, to);
  res.json(data);
});

app.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`Server started on :${PORT}`);
});