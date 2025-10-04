import { z } from 'zod';

export const masterCreateSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  phone: z.string().min(5).max(32).optional().or(z.literal('')).transform(v => v || undefined),
  bio: z.string().max(500).optional().or(z.literal('')).transform(v => v || undefined),
});

export type MasterCreateInput = z.infer<typeof masterCreateSchema>;
