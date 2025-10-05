import express, { Request, Response } from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pino from 'pino';
import pinoHttp from 'pino-http';
import cors from 'cors';

// ESM-friendly __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

const logger = pino({ level: process.env.LOG_LEVEL ?? 'info' });

// Correct pino-http usage (call the default-exported factory function)
app.use(pinoHttp({ logger }));

app.use(cors());
app.use(express.json());

app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

app.use('/public', express.static(path.join(__dirname, '../public')));

const PORT = Number(process.env.PORT ?? 8080);
app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
