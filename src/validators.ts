import { z } from 'zod';

export const serviceCreateSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  priceCents: z.number().int().min(0).default(0),
  durationMin: z.number().int().min(5).max(24 * 60),
  isActive: z.boolean().optional().default(true),
});

export const appointmentCreateSchema = z.object({
  client: z.object({
    name: z.string().optional(),
    phone: z.string().optional(),
    tgUserId: z.string().optional(),
  }).optional(),
  clientId: z.string().optional(),
  serviceId: z.string().min(1),
  masterId: z.string().optional(),
  startAt: z.string().datetime()
});
