import express, { Request, Response } from 'express';
import path from 'path';
import { PrismaClient, AppointmentStatus } from '@prisma/client';
import bodyParser from 'body-parser';
import cors from 'cors';
import { tgRouter, installWebhook as tgInstallWebhook } from './telegram';

const app = express();
const prisma = new PrismaClient();

app.use(cors());
app.use(bodyParser.json());

// ---- Health & root ----
app.get('/', (_req: Request, res: Response) => {
  res.type('html').send(`
    <h1>Онлайн‑запись</h1>
    <p>Это простая статика мини‑приложения (без сборки). Сервер: Express + Prisma.</p>
    <p><a href="/app.html">Открыть мини‑приложение</a></p>
    <p>Показать услуги (GET /api/services)</p>
  `);
});

// ---- Static ----
app.use(express.static(path.join(process.cwd())));

// ---- Public API ----
app.get('/api/services', async (_req: Request, res: Response) => {
  try {
    const services = await prisma.service.findMany({
      orderBy: { createdAt: 'asc' },
      select: { id: true, name: true, durationMin: true, priceCents: true, createdAt: true, updatedAt: true }
    });
    res.json({ ok: true, services });
  } catch (err:any) {
    console.error('[api/services] failed', err);
    res.status(500).json({ ok:false, error: err?.message || 'internal' });
  }
});

// ---- Admin: minimal services editor API ----
app.get('/admin/services', async (_req: Request, res: Response) => {
  try {
    const list = await prisma.service.findMany({ orderBy: { createdAt: 'desc' } });
    res.json({ ok: true, list });
  } catch (e:any) {
    console.error('[admin/services:list]', e);
    res.status(500).json({ ok:false, error: e?.message });
  }
});

app.post('/admin/services', async (req: Request, res: Response) => {
  try {
    const { name, description, priceCents, durationMin } = req.body || {};
    if (!name || typeof priceCents !== 'number' || typeof durationMin !== 'number') {
      return res.status(400).json({ ok:false, error:'name, priceCents:number, durationMin:number required' });
    }
    const s = await prisma.service.create({
      data: { name, description: description ?? null, priceCents, durationMin }
    });
    res.json({ ok:true, service: s });
  } catch (e:any) {
    console.error('[admin/services:create]', e);
    res.status(500).json({ ok:false, error: e?.message });
  }
});

app.put('/admin/services/:id', async (req: Request, res: Response) => {
  try {
    const id = req.params.id;
    const { name, description, priceCents, durationMin } = req.body || {};
    const s = await prisma.service.update({
      where: { id },
      data: {
        ...(name !== undefined ? { name } : {}),
        ...(description !== undefined ? { description } : {}),
        ...(priceCents !== undefined ? { priceCents: Number(priceCents) } : {}),
        ...(durationMin !== undefined ? { durationMin: Number(durationMin) } : {}),
      }
    });
    res.json({ ok:true, service: s });
  } catch (e:any) {
    console.error('[admin/services:update]', e);
    res.status(500).json({ ok:false, error: e?.message });
  }
});

app.delete('/admin/services/:id', async (req: Request, res: Response) => {
  try {
    const id = req.params.id;
    await prisma.service.delete({ where: { id } });
    res.json({ ok:true });
  } catch (e:any) {
    console.error('[admin/services:delete]', e);
    res.status(500).json({ ok:false, error: e?.message });
  }
});

// ---- Appointments (example create via public API) ----
// NOTE: we cannot upsert/findUnique by tgUserId because it is NOT unique in schema.
// We search via findFirst and create if not exists, then connect by id.
app.post('/api/appointments', async (req: Request, res: Response) => {
  try {
    const { serviceId, staffId, locationId, startAt, endAt, client } = req.body || {};
    if (!serviceId || !startAt || !endAt) {
      return res.status(400).json({ ok:false, error:'serviceId, startAt, endAt required' });
    }

    // Ensure client
    let clientId: string | null = null;
    if (client && (client.tgUserId || client.phone || client.email)) {
      const found = await prisma.client.findFirst({
        where: {
          OR: [
            client.tgUserId ? { tgUserId: String(client.tgUserId) } : undefined,
            client.phone ? { phone: String(client.phone) } : undefined,
            client.email ? { email: String(client.email) } : undefined,
          ].filter(Boolean) as any[]
        }
      });

      if (found) {
        clientId = found.id;
      } else {
        const created = await prisma.client.create({
          data: {
            tgUserId: client.tgUserId ? String(client.tgUserId) : null,
            phone: client.phone ? String(client.phone) : null,
            email: client.email ? String(client.email) : null,
            firstName: client.firstName ?? null,
            lastName: client.lastName ?? null,
          }
        });
        clientId = created.id;
      }
    }

    const appt = await prisma.appointment.create({
      data: {
        service: { connect: { id: serviceId } },
        ...(staffId ? { staff: { connect: { id: staffId } } } : {}),
        ...(locationId ? { location: { connect: { id: locationId } } } : {}),
        ...(clientId ? { client: { connect: { id: clientId } } } : {}),
        startAt: new Date(startAt),
        endAt: new Date(endAt),
        status: AppointmentStatus.CREATED,
      }
    });

    res.json({ ok:true, appointment: appt });
  } catch (e:any) {
    console.error('[api/appointments:create]', e);
    res.status(500).json({ ok:false, error: e?.message });
  }
});

// ---- Telegram routes ----
app.use('/tg', tgRouter);

// ---- Start ----
const PORT = Number(process.env.PORT || process.env.RAILWAY_TCP_PORT || 8080);

(async () => {
  app.listen(PORT, async () => {
    console.log(`[http] listening on :${PORT}`);
    try {
      await tgInstallWebhook(app);
    } catch (e) {
      console.error('[tg] setWebhook failed', e);
    }
  });
})().catch((e) => {
  console.error('fatal start error', e);
  process.exit(1);
});
