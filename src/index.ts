import express from 'express';
import cors from 'cors';
import env from './env.js';
import { logger, httpLogger } from './logger.js';
import { router as api } from './routes/index.js';

const app = express();

// Middlewares
app.use(express.json());
app.use(cors());
app.use(httpLogger);

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, env: env.NODE_ENV });
});

// API
app.use('/api', api);

const port = env.PORT;
app.listen(port, () => {
  logger.info({ port }, 'Server started');
});
