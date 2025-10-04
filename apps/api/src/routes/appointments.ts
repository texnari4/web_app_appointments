import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db';
import dayjs from 'dayjs';
import utc from 'dayjs/plugin/utc';
import { requireRole } from '../middleware/auth';
import { enqueueNotification } from '../notifications/outbox';
dayjs.extend(utc);

export const appointments = Router();

const CreateSchema = z.object({
  client_id: z.string().uuid(),
  master_id: z.string().uuid(),
  service_id: z.string().uuid(),
  start_at: z.string().datetime(),
  comment: z.string().optional()
});

appointments.post('/', requireRole('client','admin','master'), async (req, res) => {
  const parsed = CreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { client_id, master_id, service_id, start_at, comment } = parsed.data;

  const svc = await query(`
    SELECT s.duration_min, COALESCE(ms.custom_duration_min, s.duration_min) AS duration, COALESCE(ms.custom_price_minor, s.price_minor) AS price_minor
    FROM services s
    LEFT JOIN master_services ms ON ms.service_id=s.id AND ms.master_id=$1
    WHERE s.id=$2`, [master_id, service_id]);
  if (!svc.rows.length) return res.status(404).json({ error: 'service not found' });
  const durationMin = Number(svc.rows[0].duration);
  const priceMinor = Number(svc.rows[0].price_minor);

  const start = dayjs.utc(start_at);
  const end = start.add(durationMin, 'minute');

  const col = await query(
    `SELECT 1 FROM appointments WHERE master_id=$1 AND status IN ('pending','confirmed') AND NOT (end_at <= $2 OR start_at >= $3) LIMIT 1`,
    [master_id, start.toDate(), end.toDate()]
  );
  if (col.rows.length) return res.status(409).json({ error: 'Slot not available' });

  const createdBy = (req as any).auth?.role || 'client';
  const ins = await query(
    `INSERT INTO appointments(client_id, master_id, service_id, start_at, end_at, price_minor, status, comment, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,'pending',$7,$8) RETURNING id`,
    [client_id, master_id, service_id, start.toDate(), end.toDate(), priceMinor, comment || null, createdBy]
  );

  const appId = ins.rows[0].id as string;
  await enqueueNotification('tg_message', { type: 'appointment_created', appointment_id: appId });

  res.status(201).json({ id: appId });
});

appointments.get('/client', requireRole('client','admin','master'), async (req, res) => {
  const clientId = (req as any).auth?.clientId;
  if (!clientId) return res.json([]);
  const { rows } = await query(
    `SELECT a.id, a.start_at, a.end_at, a.status, s.name AS service, m.name AS master, a.price_minor
     FROM appointments a
     JOIN services s ON s.id=a.service_id
     JOIN masters m ON m.id=a.master_id
     WHERE a.client_id=$1 ORDER BY a.start_at DESC`,
    [clientId]
  );
  res.json(rows);
});
