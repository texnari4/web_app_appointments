import { Router } from 'express';
import { requireRole } from '../middleware/auth';
import { query } from '../db';

export const master = Router();

master.get('/day-schedule', requireRole('master','admin'), async (req, res) => {
  const { masterId } = (req as any).auth;
  const date = (req.query.date as string) || new Date().toISOString().slice(0,10);
  const { rows } = await query(`
    SELECT a.id, a.start_at, a.end_at, a.status, a.comment, c.first_name, c.last_name, c.phone, c.username, s.name AS service
    FROM appointments a
    JOIN clients c ON c.id=a.client_id
    JOIN services s ON s.id=a.service_id
    WHERE a.master_id=$1 AND a.start_at::date=$2::date
    ORDER BY a.start_at`, [masterId, date]);
  res.json(rows);
});

master.get('/clients', requireRole('master','admin'), async (req, res) => {
  const { masterId } = (req as any).auth;
  const { rows } = await query(`
    SELECT DISTINCT c.id, c.first_name, c.last_name, c.phone, c.username
    FROM appointments a
    JOIN clients c ON c.id = a.client_id
    WHERE a.master_id=$1
    ORDER BY c.first_name NULLS LAST`, [masterId]);
  res.json(rows);
});
