import { z } from "zod";

export const masterCreateSchema = z.object({
  name: z.string().min(1, "Имя обязательно"),
  phone: z.string().min(5, "Телефон обязателен"),
  specialty: z.string().optional(),
  photoUrl: z.string().url("Неверный URL").optional(),
});

export const masterUpdateSchema = masterCreateSchema.partial();
