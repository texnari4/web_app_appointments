import { Router } from 'express';
import { query } from '../db';
export const services = Router();

services.get('/', async (_req, res) => {
  const { rows } = await query('SELECT id, name, description, category, price_minor, duration_min FROM services WHERE active = true ORDER BY name');
  res.json(rows);
});
