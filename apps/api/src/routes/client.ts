import { Router } from 'express';
import { requireRole } from '../middleware/auth';
import { query } from '../db';

export const client = Router();

client.get('/me', requireRole('client','master','admin'), async (req, res) => {
  const { clientId } = (req as any).auth;
  if (!clientId) return res.status(404).json({});
  const { rows } = await query('SELECT id, first_name, last_name, username, phone FROM clients WHERE id=$1', [clientId]);
  res.json(rows[0] || {});
});
