
import { z } from 'zod';

export const metaCreateSchema = z.object({
  key: z.string().min(1),
  value: z.string().optional(),
});

export const masterCreateSchema = z.object({
  name: z.string().min(1),
  phone: z.string().optional(),
  isActive: z.boolean().optional(),
});

export const serviceCreateSchema = z.object({
  name: z.string().min(1),
  price: z.number().int().nonnegative(),
  durationMins: z.number().int().positive(),
  isActive: z.boolean().optional(),
});

export const linkServiceSchema = z.object({
  serviceId: z.number().int().positive(),
});

export const appointmentCreateSchema = z.object({
  masterId: z.number().int().positive(),
  serviceId: z.number().int().positive(),
  customerName: z.string().min(1),
  customerPhone: z.string().optional(),
  startsAt: z.coerce.date(),
  status: z.enum(['SCHEDULED', 'DONE', 'CANCELED']).optional(),
});

export type MetaCreate = z.infer<typeof metaCreateSchema>;
export type MasterCreate = z.infer<typeof masterCreateSchema>;
export type ServiceCreate = z.infer<typeof serviceCreateSchema>;
export type AppointmentCreate = z.infer<typeof appointmentCreateSchema>;
