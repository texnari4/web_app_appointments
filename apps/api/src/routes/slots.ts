import { Router } from 'express';
import dayjs from 'dayjs';
import utc from 'dayjs/plugin/utc';
import { query } from '../db';
import { generateStepSlots, subtractIntervals, glueContinuous, findStartsForDuration } from '../scheduling/slotEngine';
dayjs.extend(utc);

export const slots = Router();

slots.get('/', async (req, res) => {
  const { master_id, service_id, date } = req.query as any;
  if (!master_id || !service_id || !date) return res.status(400).json({ error: 'master_id, service_id, date required' });

  const day = dayjs.utc(String(date));
  const svc = await query(`
    SELECT s.duration_min, COALESCE(ms.custom_duration_min, s.duration_min) AS duration, COALESCE(ms.custom_price_minor, s.price_minor) AS price_minor
    FROM services s
    LEFT JOIN master_services ms ON ms.service_id=s.id AND ms.master_id=$1
    WHERE s.id=$2`, [master_id, service_id]);
  if (!svc.rows.length) return res.status(404).json({ error: 'service not found' });
  const durationMin = Number(svc.rows[0].duration);

  const weekday = (day.day() + 6) % 7;
  const wh = await query(`SELECT start_time_min, end_time_min, slot_step_min FROM master_working_hours WHERE master_id=$1 AND weekday=$2`, [master_id, weekday]);
  if (!wh.rows.length) return res.json({ slots: [] });
  const { start_time_min, end_time_min, slot_step_min } = wh.rows[0];

  const baseSlots = generateStepSlots(day.toDate(), slot_step_min, start_time_min, end_time_min);

  const startDay = day.startOf('day').toDate();
  const endDay = day.endOf('day').toDate();
  const appts = await query(`SELECT start_at, end_at FROM appointments WHERE master_id=$1 AND status IN ('pending','confirmed') AND start_at >= $2 AND start_at < $3`, [master_id, startDay, endDay]);
  const ovs = await query(`SELECT start_at, end_at, type FROM schedule_overrides WHERE master_id=$1 AND start_at < $3 AND end_at > $2`, [master_id, startDay, endDay]);

  const busy: Array<{start: Date; end: Date}> = [];
  for (const a of appts.rows) busy.push({ start: new Date(a.start_at), end: new Date(a.end_at) });
  for (const o of ovs.rows) if (o.type !== 'open') busy.push({ start: new Date(o.start_at), end: new Date(o.end_at) });

  const free = subtractIntervals(baseSlots, busy);
  const glued = glueContinuous(free);
  const starts = findStartsForDuration(glued, durationMin, slot_step_min);

  res.json({ date: day.format('YYYY-MM-DD'), step_min: slot_step_min, duration_min: durationMin, slots: starts.map(d => d.toISOString()) });
});
