import express, { type Request, type Response } from 'express';
import path from 'node:path';
import cors from 'cors';
import { addMaster, listMasters, setMasterActive } from './db.js';

const app = express();
const PORT = Number(process.env.PORT || 8080);

// Middlewares
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Serve static under /public with correct MIME
const publicDir = path.join(process.cwd(), 'public');
app.use('/public', express.static(publicDir, { fallthrough: true }));

// Health
app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Admin page (send HTML file)
app.get(['/admin','/admin/'], (_req: Request, res: Response) => {
  res.sendFile(path.join(publicDir, 'admin', 'index.html'));
});

// API
app.get(['/api/masters','/public/api/masters'], async (_req: Request, res: Response) => {
  const items = await listMasters();
  res.json({ items });
});

app.post(['/api/masters','/public/api/masters'], async (req: Request, res: Response) => {
  try {
    const { name, phone, avatarUrl, isActive } = req.body ?? {};
    if (!name || !phone) {
      res.status(400).json({ error: 'name and phone are required' });
      return;
    }
    const created = await addMaster({
      name,
      phone,
      avatarUrl,
      isActive: isActive ?? true,
    });
    res.status(201).json({ item: created });
  } catch (e) {
    res.status(500).json({ error: 'failed_to_create' });
  }
});

app.post(['/api/masters/:id/toggle','/public/api/masters/:id/toggle'], async (req: Request, res: Response) => {
  const { id } = req.params;
  const { isActive } = req.body ?? {};
  const updated = await setMasterActive(id, Boolean(isActive));
  if (!updated) {
    res.status(404).json({ error: 'not_found' });
    return;
  }
  res.json({ item: updated });
});

// Root -> not found
app.get('/', (_req: Request, res: Response) => {
  res.status(404).json({ error: 'NOT_FOUND' });
});

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});