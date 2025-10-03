import express, { Request, Response } from 'express';
import path from 'path';
import { prisma, ensureDb } from './prisma';
import { tgRouter, installWebhook } from './telegram';

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// serve static
const publicDir = path.join(process.cwd(), 'public');
app.use(express.static(publicDir));

// Health
app.get('/health', (_req: Request, res: Response) => res.json({ ok: true }));

// ---- Services CRUD ----
app.get('/api/services', async (_req: Request, res: Response) => {
  try {
    const items = await prisma.service.findMany({
      select: { id: true, name: true, description: true, durationMin: true, priceCents: true, createdAt: true, updatedAt: true },
      orderBy: { name: 'asc' },
    });
    res.json(items.map(s => ({
      ...s,
      priceBYN: (s.priceCents / 100).toFixed(2),
    })));
  } catch (e: any) {
    console.error(e);
    res.status(500).json({ error: 'failed_list_services', detail: String(e?.message || e) });
  }
});

app.post('/api/services', async (req: Request, res: Response) => {
  try {
    const { name, description, durationMin, priceCents } = req.body;
    const created = await prisma.service.create({
      data: {
        name: String(name),
        description: description ? String(description) : null,
        durationMin: Number(durationMin),
        priceCents: Number(priceCents),
      },
    });
    res.status(201).json(created);
  } catch (e: any) {
    console.error(e);
    res.status(400).json({ error: 'failed_create_service', detail: String(e?.message || e) });
  }
});

app.put('/api/services/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const { name, description, durationMin, priceCents } = req.body;
    const updated = await prisma.service.update({
      where: { id },
      data: {
        name: name !== undefined ? String(name) : undefined,
        description: description !== undefined ? (description ? String(description) : null) : undefined,
        durationMin: durationMin !== undefined ? Number(durationMin) : undefined,
        priceCents: priceCents !== undefined ? Number(priceCents) : undefined,
      },
    });
    res.json(updated);
  } catch (e: any) {
    console.error(e);
    res.status(400).json({ error: 'failed_update_service', detail: String(e?.message || e) });
  }
});

app.delete('/api/services/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    await prisma.service.delete({ where: { id } });
    res.status(204).send();
  } catch (e: any) {
    console.error(e);
    res.status(400).json({ error: 'failed_delete_service', detail: String(e?.message || e) });
  }
});

// ---- Slots ----
// GET /api/slots?serviceId=&staffId=&date=YYYY-MM-DD
app.get('/api/slots', async (req: Request, res: Response) => {
  try {
    const serviceId = String(req.query.serviceId || '');
    const staffId = String(req.query.staffId || '');
    const dateStr = String(req.query.date || '');
    if (!serviceId || !staffId || !dateStr) {
      return res.status(400).json({ error: 'bad_request', detail: 'serviceId, staffId, date are required' });
    }
    const service = await prisma.service.findUnique({ where: { id: serviceId } });
    if (!service) return res.status(404).json({ error: 'service_not_found' });
    const duration = service.durationMin;

    // work window 10:00 - 20:00 local
    const day = new Date(dateStr + 'T00:00:00.000Z');
    const start = new Date(day); start.setUTCHours(7, 0, 0, 0)  // assume local GMT+3 -> 10:00 local ~ 07:00Z
    const end   = new Date(day); end.setUTCHours(17, 0, 0, 0)  // 20:00 local ~ 17:00Z

    // existing appointments for staff that day
    const appointments = await prisma.appointment.findMany({
      where: {
        staffId,
        startAt: { gte: start, lt: end },
      },
      select: { startAt: true, endAt: true },
    });

    const slots: string[] = [];
    function addMinutes(d: Date, m: number) {
      return new Date(d.getTime() + m * 60000);
    }
    for (let t = new Date(start); addMinutes(t, duration) <= end; t = addMinutes(t, 30)) {
      const slotStart = new Date(t);
      const slotEnd = addMinutes(slotStart, duration);
      const overlap = appointments.some(a => !(slotEnd <= a.startAt || slotStart >= a.endAt));
      if (!overlap) slots.push(slotStart.toISOString());
    }
    res.json({ slots, durationMin: duration });
  } catch (e: any) {
    console.error(e);
    res.status(500).json({ error: 'failed_slots', detail: String(e?.message || e) });
  }
});

// ---- Appointments ----
// POST /api/appointments { serviceId, staffId, startAtISO, client: { tgUserId?, phoneEnc?, emailEnc?, firstName?, lastName? } }
app.post('/api/appointments', async (req: Request, res: Response) => {
  try {
    const { serviceId, staffId, startAtISO, client } = req.body || {};
    if (!serviceId || !staffId || !startAtISO || !client) {
      return res.status(400).json({ error: 'bad_request', detail: 'serviceId, staffId, startAtISO, client required' });
    }
    const service = await prisma.service.findUnique({ where: { id: String(serviceId) } });
    if (!service) return res.status(404).json({ error: 'service_not_found' });
    const startAt = new Date(String(startAtISO));
    const endAt = new Date(startAt.getTime() + service.durationMin * 60000);

    // ensure client (upsert by tgUserId if provided)
    let clientId: string | undefined;
    if (client.tgUserId) {
      const c = await prisma.client.upsert({
        where: { tgUserId: String(client.tgUserId) },
        update: {
          phoneEnc: client.phoneEnc ?? undefined,
          emailEnc: client.emailEnc ?? undefined,
          firstName: client.firstName ?? undefined,
          lastName: client.lastName ?? undefined,
        },
        create: {
          tgUserId: String(client.tgUserId),
          phoneEnc: client.phoneEnc ?? null,
          emailEnc: client.emailEnc ?? null,
          firstName: client.firstName ?? null,
          lastName: client.lastName ?? null,
        },
      });
      clientId = c.id;
    } else {
      const c = await prisma.client.create({
        data: {
          phoneEnc: client.phoneEnc ?? null,
          emailEnc: client.emailEnc ?? null,
          firstName: client.firstName ?? null,
          lastName: client.lastName ?? null,
        },
      });
      clientId = c.id;
    }

    // collision check
    const exists = await prisma.appointment.findFirst({
      where: {
        staffId: String(staffId),
        OR: [
          { AND: [{ startAt: { lt: endAt } }, { endAt: { gt: startAt } }] },
        ],
      },
    });
    if (exists) return res.status(409).json({ error: 'slot_taken' });

    const created = await prisma.appointment.create({
      data: {
        serviceId: String(serviceId),
        staffId: String(staffId),
        clientId: clientId!,
        startAt,
        endAt,
        status: 'CREATED',
      },
    });

    console.log('[appt] created', created.id);
    res.status(201).json(created);
  } catch (e: any) {
    console.error(e);
    res.status(400).json({ error: 'failed_create_appointment', detail: String(e?.message || e) });
  }
});

// ---- Admin (static page) ----
app.get('/admin/services', (_req: Request, res: Response) => {
  res.sendFile(path.join(publicDir, 'admin-services.html'));
});

// Telegram routes
app.use('/tg', tgRouter);

// Root page
app.get('/', (_req: Request, res: Response) => {
  res.sendFile(path.join(publicDir, 'index.html'));
});

const PORT = Number(process.env.PORT || 8080);

async function main() {
  try {
    await ensureDb();
  } catch (e) {
    console.error('[db] ping failed', e);
  }
  app.listen(PORT, async () => {
    console.log(`[http] listening on :${PORT}`);
    const baseUrl = process.env.RAILWAY_URL || '';
    const botToken = process.env.TELEGRAM_BOT_TOKEN || '';
    if (baseUrl && botToken) {
      await installWebhook(baseUrl, botToken);
    }
  });
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
