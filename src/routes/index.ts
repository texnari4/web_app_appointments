import { Router } from 'express';
import { prisma } from '../prisma.js';
import { z } from 'zod';

export const router = Router();

// GET /api/services - list services
router.get('/services', async (_req, res) => {
  const services = await prisma.service.findMany({ orderBy: { name: 'asc' } });
  res.json({ items: services });
});

// POST /api/services - create service
router.post('/services', async (req, res) => {
  const Body = z.object({
    name: z.string().min(1),
    description: z.string().optional(),
    priceCents: z.number().int().nonnegative(),
    durationMin: z.number().int().positive(),
  });
  const parsed = Body.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const svc = await prisma.service.create({ data: parsed.data });
  res.status(201).json(svc);
});
