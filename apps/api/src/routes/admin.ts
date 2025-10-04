import { Router } from 'express';
import { requireRole } from '../middleware/auth';
import { query } from '../db';
export const admin = Router();

admin.use(requireRole('admin'));

admin.get('/appointments', async (req, res) => {
  const { from, to, master_id, client_id, service_id } = req.query as any;
  const conds: string[] = [];
  const params: any[] = [];
  if (from) { params.push(from); conds.push(`a.start_at >= $${params.length}`); }
  if (to) { params.push(to); conds.push(`a.start_at < $${params.length}`); }
  if (master_id) { params.push(master_id); conds.push(`a.master_id = $${params.length}`); }
  if (client_id) { params.push(client_id); conds.push(`a.client_id = $${params.length}`); }
  if (service_id) { params.push(service_id); conds.push(`a.service_id = $${params.length}`); }
  const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
  const sql = `
    SELECT a.id, a.start_at, a.end_at, a.status, s.name as service, m.name as master, c.first_name || ' ' || COALESCE(c.last_name,'') as client, a.price_minor
    FROM appointments a
    JOIN services s ON s.id=a.service_id
    JOIN masters m ON m.id=a.master_id
    JOIN clients c ON c.id=a.client_id
    ${where}
    ORDER BY a.start_at DESC
  `;
  const { rows } = await query(sql, params);
  res.json(rows);
});

admin.post('/services', async (req, res) => {
  const { name, description, category, price_minor, duration_min, active } = req.body;
  const { rows } = await query(
    `INSERT INTO services(name, description, category, price_minor, duration_min, active) VALUES($1,$2,$3,$4,$5,COALESCE($6,true)) RETURNING *`,
    [name, description, category, price_minor, duration_min, active]
  );
  res.status(201).json(rows[0]);
});

admin.put('/services/:id', async (req, res) => {
  const id = req.params.id;
  const { name, description, category, price_minor, duration_min, active } = req.body;
  const { rows } = await query(
    `UPDATE services SET name=$2, description=$3, category=$4, price_minor=$5, duration_min=$6, active=$7, updated_at=NOW() WHERE id=$1 RETURNING *`,
    [id, name, description, category, price_minor, duration_min, active]
  );
  res.json(rows[0]);
});

admin.delete('/services/:id', async (req, res) => {
  const id = req.params.id;
  await query(`DELETE FROM services WHERE id=$1`, [id]);
  res.status(204).send();
});

admin.post('/masters', async (req, res) => {
  const { name, photo_url, description, specialties, phone, telegram_user_id, active } = req.body;
  const { rows } = await query(
    `INSERT INTO masters(name, photo_url, description, specialties, phone, telegram_user_id, active) VALUES($1,$2,$3,$4,$5,$6,COALESCE($7,true)) RETURNING *`,
    [name, photo_url, description, specialties || [], phone, telegram_user_id, active]
  );
  res.status(201).json(rows[0]);
});

admin.put('/masters/:id', async (req, res) => {
  const id = req.params.id;
  const { name, photo_url, description, specialties, phone, telegram_user_id, active } = req.body;
  const { rows } = await query(
    `UPDATE masters SET name=$2, photo_url=$3, description=$4, specialties=$5, phone=$6, telegram_user_id=$7, active=$8, updated_at=NOW() WHERE id=$1 RETURNING *`,
    [id, name, photo_url, description, specialties || [], phone, telegram_user_id, active]
  );
  res.json(rows[0]);
});

admin.delete('/masters/:id', async (req, res) => {
  const id = req.params.id;
  await query(`DELETE FROM masters WHERE id=$1`, [id]);
  res.status(204).send();
});
