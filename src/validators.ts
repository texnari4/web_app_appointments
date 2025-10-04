
import { z } from 'zod';

export const masterCreateSchema = z.object({
  name: z.string().min(1, 'name is required'),
  phone: z.string().optional().nullable(),
  about: z.string().optional().nullable(),
  avatarUrl: z.string().url().optional().nullable(),
});

export type MasterCreateInput = z.infer<typeof masterCreateSchema>;
