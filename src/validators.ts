import { z } from "zod";

export const createServiceSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  price: z.number().nonnegative(),
  durationMin: z.number().int().positive()
});

export const createMasterSchema = z.object({
  name: z.string().min(1),
  phone: z.string().optional(),
  specialties: z.array(z.string()).default([])
});

export const createAppointmentSchema = z.object({
  serviceId: z.string().uuid(),
  masterId: z.string().uuid(),
  clientName: z.string().min(1),
  clientPhone: z.string().min(5),
  startsAt: z.string().datetime(),
  durationMin: z.number().int().positive().optional()
});

export type CreateServiceInput = z.infer<typeof createServiceSchema>;
export type CreateMasterInput = z.infer<typeof createMasterSchema>;
export type CreateAppointmentInput = z.infer<typeof createAppointmentSchema>;