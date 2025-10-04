import { z } from 'zod';

export const exampleSchema = z.object({
  id: z.string().uuid().optional(),
  name: z.string().min(1),
});

export type Example = z.infer<typeof exampleSchema>;
