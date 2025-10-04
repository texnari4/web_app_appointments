import { Router } from 'express';
import { query } from '../db';
export const masters = Router();

masters.get('/', async (req, res) => {
  const serviceId = req.query.service_id as string | undefined;
  if (serviceId) {
    const sql = `
      SELECT m.id, m.name, m.photo_url, m.description, m.specialties
      FROM masters m
      JOIN master_services ms ON ms.master_id = m.id
      WHERE m.active=true AND ms.service_id=$1
      ORDER BY m.name
    `;
    const { rows } = await query(sql, [serviceId]);
    return res.json(rows);
  } else {
    const { rows } = await query('SELECT id, name, photo_url, description, specialties FROM masters WHERE active = true ORDER BY name');
    return res.json(rows);
  }
});
