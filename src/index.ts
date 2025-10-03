import express, { Request, Response } from 'express';
import path from 'path';
import { prisma } from './prisma';
import { installWebhook, telegramRouter } from './telegram';

const app = express();
app.use(express.json());

// Health
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true });
});

// Пример API
app.get('/api/services', async (_req: Request, res: Response) => {
  const services = await prisma.service.findMany({
    orderBy: { name: 'asc' }
  });
  res.json(services);
});

app.post('/api/appointments', async (req: Request, res: Response) => {
  try {
    const { client, serviceId, staffId, locationId, startAt, endAt } = req.body as any;

    const created = await prisma.appointment.create({
      data: {
        serviceId,
        staffId,
        locationId,
        client: client?.id
          ? { connect: { id: client.id } }
          : {
              create: {
                tgUserId: client?.tgUserId ?? null,
                phoneEnc: client?.phoneEnc ?? null,
                emailEnc: client?.emailEnc ?? null,
                firstName: client?.firstName ?? null,
                lastName: client?.lastName ?? null
              }
            },
        startAt: new Date(startAt),
        endAt: new Date(endAt),
        status: 'CREATED'
      }
    });

    res.status(201).json(created);
  } catch (err) {
    console.error(err);
    res.status(400).json({ error: 'invalid_payload' });
  }
});

// Telegram webhook
app.post('/tg/webhook', telegramRouter);

// Статика
app.use(express.static(path.join(__dirname, '..', 'public')));

app.get('/', (_req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

const port = Number(process.env.PORT ?? 3000);
const baseUrl = process.env.PUBLIC_BASE_URL ?? process.env.RAILWAY_URL;

app.listen(port, async () => {
  console.log(`[http] listening on :${port}`);

  // автоустановка вебхука (опционально)
  if (process.env.AUTO_SET_WEBHOOK === 'true' && baseUrl && process.env.TELEGRAM_BOT_TOKEN) {
    try {
      await installWebhook(`${baseUrl}/tg/webhook`);
      console.log(`[tg] setWebhook OK → ${baseUrl}/tg/webhook`);
    } catch (e) {
      console.error('[tg] setWebhook failed', e);
    }
  }
});