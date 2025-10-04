import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import pinoHttp from 'pino-http';
import path from 'path';
import { fileURLToPath } from 'url';
import { config } from './config';
import { telegramAuthMiddleware } from './auth/telegram';
import { services } from './routes/services';
import { masters } from './routes/masters';
import { availability } from './routes/availability';
import { slots } from './routes/slots';
import { appointments } from './routes/appointments';
import { client } from './routes/client';
import { master } from './routes/master';
import { admin } from './routes/admin';
import { reports } from './routes/reports';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(pinoHttp());

app.get('/healthz', (_req, res) => res.send('ok'));

app.use('/api', telegramAuthMiddleware);

app.use('/api/services', services);
app.use('/api/masters', masters);
app.use('/api/availability', availability);
app.use('/api/slots', slots);
app.use('/api/appointments', appointments);
app.use('/api/client', client);
app.use('/api/master', master);
app.use('/api/admin', admin);
app.use('/api/reports', reports);

const staticDir = path.resolve(__dirname, '../../miniapp/dist');
app.use(express.static(staticDir));
app.get('*', (req, res, next) => {
  if (req.path.startsWith('/api')) return next();
  res.sendFile(path.join(staticDir, 'index.html'), (err) => {
    if (err) next();
  });
});

app.listen(config.port, () => {
  console.log(`API listening on :${config.port}`);
});
