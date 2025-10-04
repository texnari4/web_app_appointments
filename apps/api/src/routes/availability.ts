import { Router } from 'express';
import dayjs from 'dayjs';
import utc from 'dayjs/plugin/utc';
import { query } from '../db';
import { generateStepSlots, subtractIntervals, glueContinuous } from '../scheduling/slotEngine';
dayjs.extend(utc);

export const availability = Router();

availability.get('/', async (req, res) => {
  const masterId = req.query.master_id as string;
  const month = (req.query.month as string) || dayjs().utc().format('YYYY-MM');
  if (!masterId) return res.status(400).json({ error: 'master_id required' });

  const start = dayjs.utc(month + '-01');
  const end = start.endOf('month');

  const wh = await query(`SELECT weekday, start_time_min, end_time_min, slot_step_min FROM master_working_hours WHERE master_id=$1`, [masterId]);
  const map = new Map<number, {start:number,end:number,step:number}>();
  for (const r of wh.rows) map.set(Number(r.weekday), { start: r.start_time_min, end: r.end_time_min, step: r.slot_step_min });

  const ov = await query(`SELECT start_at, end_at, type FROM schedule_overrides WHERE master_id=$1 AND start_at < $3 AND end_at > $2`, [masterId, start.toDate(), end.toDate()]);
  const app = await query(`SELECT start_at, end_at FROM appointments WHERE master_id=$1 AND status IN ('pending','confirmed') AND start_at >= $2 AND start_at < $3`, [masterId, start.toDate(), end.toDate()]);

  const days: number[] = [];
  for (let d=1; d<=end.date(); d++) {
    const cur = start.date(d);
    const weekday = (cur.day() + 6) % 7;
    const tpl = map.get(weekday);
    if (!tpl) continue;

    const slots = generateStepSlots(cur.toDate(), tpl.step, tpl.start, tpl.end);
    if (!slots.length) continue;

    const startDay = cur.startOf('day').toDate();
    const endDay = cur.endOf('day').toDate();

    const busy: { start: Date; end: Date }[] = [];
    for (const a of app.rows) {
      const s = new Date(a.start_at);
      if (s >= startDay && s <= endDay) busy.push({ start: new Date(a.start_at), end: new Date(a.end_at) });
    }
    for (const o of ov.rows) {
      const s = new Date(o.start_at);
      const e = new Date(o.end_at);
      if (e <= startDay || s >= endDay) continue;
      if (o.type !== 'open') busy.push({ start: new Date(Math.max(s.getTime(), startDay.getTime())), end: new Date(Math.min(e.getTime(), endDay.getTime())) });
    }

    const free = subtractIntervals(slots, busy);
    const glued = glueContinuous(free);
    if (glued.length) days.push(d);
  }

  res.json({ month, available_days: days });
});
