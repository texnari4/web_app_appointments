// Minimal Express + Prisma + Zod + Pino (Node 22, CJS)
import express from 'express';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const app = express();

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
app.use(pinoHttp({ logger }));

app.use(cors());
app.use(express.json());

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Static
app.use(express.static('public'));
app.get('/', (_req, res) => {
  res.sendFile('index.html', { root: 'public' });
});
app.get('/admin', (_req, res) => {
  res.sendFile('admin/index.html', { root: 'public' });
});

// --- API ---
const mastersRouter = express.Router();
mastersRouter.get('/masters', async (_req, res) => {
  res.json({ ok: true, data: [] });
});
app.use('/api', mastersRouter);
app.use('/public/api', mastersRouter);

// 404 for API
app.use('/api', (_req, res) => res.status(404).json({ ok: false, error: 'Not found' }));

// Global 404
app.use((_req, res) => res.status(404).send('Not Found'));

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
