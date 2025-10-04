import { z } from 'zod';

export const createMasterSchema = z.object({
  name: z.string().min(1).max(100)
});

export const createServiceSchema = z.object({
  title: z.string().min(1).max(100),
  priceCents: z.number().int().nonnegative(),
  durationMin: z.number().int().positive()
});

export const createAppointmentSchema = z.object({
  masterId: z.string().min(1),
  serviceId: z.string().min(1),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
  customerName: z.string().min(1).max(120),
  customerPhone: z.string().min(5).max(32)
});

export type CreateMasterInput = z.infer<typeof createMasterSchema>;
export type CreateServiceInput = z.infer<typeof createServiceSchema>;
export type CreateAppointmentInput = z.infer<typeof createAppointmentSchema>;
