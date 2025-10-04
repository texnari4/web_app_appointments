import express from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';
import { prisma } from './prisma';
import { z } from 'zod';

const app = express();
app.use(express.json());
app.use(cors());
app.use(pinoHttp());

const PingSchema = z.object({ ping: z.literal('pong') });

app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

app.post('/validate', (req, res) => {
  const parsed = PingSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json(parsed.error.flatten());
  res.json({ ok: true });
});

const port = Number(process.env.PORT || 8080);
app.listen(port, '0.0.0.0', () => {
  console.log(`Server started on :${port}`);
});
