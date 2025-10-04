import { z } from 'zod';

export const MasterCreateSchema = z.object({
  name: z.string().min(1),
});

export const ServiceCreateSchema = z.object({
  title: z.string().min(1),
  priceCents: z.number().int().min(0),
  durationMin: z.number().int().positive(),
});

export const AppointmentCreateSchema = z.object({
  masterId: z.string().min(1),
  serviceId: z.string().min(1),
  startsAt: z.coerce.date(),
  endsAt: z.coerce.date(),
  customerName: z.string().min(1),
  customerPhone: z.string().min(5),
}).refine((data) => data.startsAt < data.endsAt, {
  message: "startsAt must be before endsAt",
  path: ["startsAt"],
});