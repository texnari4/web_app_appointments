import { z } from 'zod';

export const masterCreateSchema = z.object({
  name: z.string().min(1).max(100).transform(v => v.trim()),
  phone: z.string().optional().transform(v => (v ?? '').trim()).refine(v => (v === '' || /^\+?[0-9\-\s]{7,20}$/.test(v)), 'Invalid phone format'),
});

export type MasterCreateInput = z.infer<typeof masterCreateSchema>;
