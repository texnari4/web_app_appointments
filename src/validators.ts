import { z } from 'zod';

export const MasterCreateSchema = z.object({
  name: z.string().min(2, 'Введите имя от 2 символов').max(64, 'Слишком длинное имя')
});

export type MasterCreateInput = z.infer<typeof MasterCreateSchema>;
