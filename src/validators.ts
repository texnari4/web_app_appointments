import { z } from 'zod';

export const masterCreateSchema = z.object({
  name: z.string().trim().min(1, 'Введите имя').max(100, 'Слишком длинное имя'),
});

export type MasterCreateInput = z.infer<typeof masterCreateSchema>;