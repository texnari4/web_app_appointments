import { z } from "zod";

export const serviceCreateSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  price: z.number().int().nonnegative(),
  durationMin: z.number().int().positive(),
});

export const serviceUpdateSchema = serviceCreateSchema.partial();

export const appointmentCreateSchema = z.object({
  clientId: z.string().min(1),
  masterId: z.string().min(1),
  serviceId: z.string().min(1),
  startsAt: z.string().datetime({ offset: true }),
  note: z.string().optional(),
});
