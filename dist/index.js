import express from 'express';
import path from 'node:path';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { db } from './db.js';
const PORT = Number(process.env.PORT || 8080);
const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const app = express();
const logger = pino();
app.use(pinoHttp({ logger }));
app.use(cors());
app.use(express.json());
// Статика: /public/* (CSS/JS/картинки и т.д.)
app.use('/public', express.static(path.join(process.cwd(), 'public'), { fallthrough: true }));
/** ----------- Masters ----------- */
app.get('/public/api/masters', async (_req, res) => {
    res.json({ items: await db.listMasters() });
});
app.post('/public/api/masters', async (req, res) => {
    const created = await db.upsertMaster(req.body || {});
    res.json(created);
});
app.put('/public/api/masters/:id', async (req, res) => {
    const created = await db.upsertMaster({ ...(req.body || {}), id: req.params.id });
    res.json(created);
});
app.delete('/public/api/masters/:id', async (req, res) => {
    res.json(await db.deleteMaster(req.params.id));
});
/** ----------- Services ----------- */
app.get('/public/api/services', async (_req, res) => {
    res.json({ items: await db.listServices() });
});
app.post('/public/api/services', async (req, res) => {
    const created = await db.upsertService(req.body || {});
    res.json(created);
});
app.put('/public/api/services/:id', async (req, res) => {
    const created = await db.upsertService({ ...(req.body || {}), id: req.params.id });
    res.json(created);
});
app.delete('/public/api/services/:id', async (req, res) => {
    res.json(await db.deleteService(req.params.id));
});
/** ----------- Appointments ----------- */
app.get('/public/api/appointments', async (_req, res) => {
    res.json({ items: await db.listAppointments() });
});
app.post('/public/api/appointments', async (req, res) => {
    const created = await db.upsertAppointment(req.body || {});
    res.json(created);
});
app.put('/public/api/appointments/:id', async (req, res) => {
    const created = await db.upsertAppointment({ ...(req.body || {}), id: req.params.id });
    res.json(created);
});
app.delete('/public/api/appointments/:id', async (req, res) => {
    res.json(await db.deleteAppointment(req.params.id));
});
/** ----------- Clients ----------- */
app.get('/public/api/clients', async (_req, res) => {
    res.json({ items: await db.listClients() });
});
app.post('/public/api/clients', async (req, res) => {
    const created = await db.upsertClient(req.body || {});
    res.json(created);
});
app.put('/public/api/clients/:id', async (req, res) => {
    const created = await db.upsertClient({ ...(req.body || {}), id: req.params.id });
    res.json(created);
});
app.delete('/public/api/clients/:id', async (req, res) => {
    res.json(await db.deleteClient(req.params.id));
});
/** ----------- Admin UI ----------- */
// /admin — отдаем готовую страницу из public/admin/index.html
app.get(['/admin', '/admin/'], (_req, res) => {
    res.sendFile(path.join(process.cwd(), 'public', 'admin', 'index.html'));
});
app.get('/', (_req, res) => {
    res.type('text').send(`OK
DATA_DIR=${DATA_DIR}
`);
});
app.listen(PORT, () => {
    logger.info(`Server started on :${PORT}`);
    logger.info(`DATA_DIR=${DATA_DIR}`);
});
