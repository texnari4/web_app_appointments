import express from 'express';
import cors from 'cors';
import pino from 'pino';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const logger = pino();

const PORT = Number(process.env.PORT) || 8080;

app.use(cors());
app.use(express.json());

// minimal request logger (no pino-http)
app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    logger.info({
      method: req.method,
      url: req.originalUrl,
      status: res.statusCode,
      ms: Date.now() - started
    });
  });
  next();
});

// health
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// static assets
app.use('/public', express.static(path.join(__dirname, '../public')));

// fallback 404
app.use((_req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
