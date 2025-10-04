import { Router } from 'express';
import { requireRole } from '../middleware/auth';
import { query } from '../db';
export const reports = Router();

reports.use(requireRole('admin'));

reports.get('/popular-services', async (req, res) => {
  const { from, to } = req.query;
  const { rows } = await query(`
    SELECT s.name, COUNT(*)::int AS count
    FROM appointments a JOIN services s ON s.id=a.service_id
    WHERE a.status IN ('confirmed','completed')
      AND a.start_at BETWEEN $1 AND $2
    GROUP BY s.name
    ORDER BY count DESC LIMIT 20
  `, [from, to]);
  res.json(rows);
});

reports.get('/revenue-by-master', async (req, res) => {
  const { from, to } = req.query;
  const { rows } = await query(`
    SELECT m.name, SUM(a.price_minor)::bigint AS revenue_minor
    FROM appointments a JOIN masters m ON m.id=a.master_id
    WHERE a.status IN ('confirmed','completed')
      AND a.start_at BETWEEN $1 AND $2
    GROUP BY m.name ORDER BY revenue_minor DESC`, [from, to]);
  res.json(rows);
});
