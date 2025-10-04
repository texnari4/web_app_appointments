import { z } from 'zod';

export const masterCreateSchema = z.object({
  name: z.string().min(1, "Имя обязательно").max(100, "Слишком длинное имя")
});

export type MasterCreateInput = z.infer<typeof masterCreateSchema>;
