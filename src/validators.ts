import { z } from 'zod';

export const masterCreateSchema = z.object({
  name: z.string().min(1).max(120),
  isActive: z.boolean().optional().default(true)
});

export type MasterCreateInput = z.infer<typeof masterCreateSchema>;
