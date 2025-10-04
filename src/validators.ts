import { z } from 'zod';

export const MasterCreateSchema = z.object({
  name: z.string().min(1),
});
export type MasterCreateInput = z.infer<typeof MasterCreateSchema>;

export const ServiceCreateSchema = z.object({
  title: z.string().min(1),
  priceCents: z.number().int().nonnegative(),
  durationMin: z.number().int().positive(),
});
export type ServiceCreateInput = z.infer<typeof ServiceCreateSchema>;

export const AppointmentCreateSchema = z.object({
  masterId: z.string().min(1),
  serviceId: z.string().min(1),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
  customerName: z.string().min(1),
  customerPhone: z.string().min(5),
});
export type AppointmentCreateInput = z.infer<typeof AppointmentCreateSchema>;
