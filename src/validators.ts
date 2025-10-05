import { z } from 'zod';

export const masterCreateSchema = z.object({
  name: z.string().min(2).max(80),
  phone: z.string().min(5).max(32).optional(),
  about: z.string().max(280).optional()
});

export type MasterCreateInput = z.infer<typeof masterCreateSchema>;
