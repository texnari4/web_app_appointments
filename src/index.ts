import express, { Request, Response } from 'express';
import path from 'path';
import { prisma } from './prisma';
import { installWebhook, telegramRouter } from './telegram';

const app = express();
app.use(express.json());

// Health-check
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true });
});

// Получение списка услуг
app.get('/api/services', async (_req: Request, res: Response) => {
  const services = await prisma.service.findMany({
    orderBy: { name: 'asc' }
  });
  res.json(services);
});

// Создание записи на приём
app.post('/api/appointments', async (req: Request, res: Response) => {
  try {
    const { locationId, serviceId, staffId, client } = req.body;

    const appointment = await prisma.appointment.create({
      data: {
        // Указываем связи через relation-объекты
        location: { connect: { id: locationId } },
        service:  { connect: { id: serviceId } },
        staff:    { connect: { id: staffId } },
        // Клиент: либо connect по id, либо create с разрешёнными полями
        client: client?.id
          ? { connect: { id: client.id } }
          : {
              create: {
                tgUserId:  client?.tgUserId  ?? null,
                firstName: client?.firstName ?? null,
                lastName:  client?.lastName  ?? null,
                phone:     client?.phone     ?? null,
                email:     client?.email     ?? null
              }
            },
        startAt: new Date(),
        endAt:   new Date(Date.now() + 60 * 60 * 1000),
        status:  'CREATED'
      }
    });

    res.status(201).json(appointment);
  } catch (err) {
    console.error(err);
    res.status(400).json({ error: 'invalid_payload' });
  }
});

// Обработчик Telegram webhook
app.post('/tg/webhook', telegramRouter);

// Отдача статических файлов
app.use(express.static(path.join(__dirname, '..', 'public')));
app.get('/', (_req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

// Запуск сервера
const port    = Number(process.env.PORT ?? 3000);
const baseUrl = process.env.PUBLIC_BASE_URL ?? process.env.RAILWAY_URL ?? '';

app.listen(port, async () => {
  console.log(`[http] listening on :${port}`);

  // Автоматическая установка webhook (если включена)
  if (process.env.AUTO_SET_WEBHOOK === 'true' && baseUrl && process.env.TELEGRAM_BOT_TOKEN) {
    try {
      await installWebhook(`${baseUrl}/tg/webhook`);
      console.log(`[tg] setWebhook OK → ${baseUrl}/tg/webhook`);
    } catch (e) {
      console.error('[tg] setWebhook failed', e);
    }
  }
});