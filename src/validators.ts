import { z } from "zod";

export const MasterCreateSchema = z.object({
  name: z.string().min(1, "name is required").max(120),
  phone: z.string().min(5).max(32).optional(),
  bio: z.string().max(2000).optional(),
});
export type MasterCreateInput = z.infer<typeof MasterCreateSchema>;

export const MasterUpdateSchema = MasterCreateSchema.partial();
export type MasterUpdateInput = z.infer<typeof MasterUpdateSchema>;

export const IdParamSchema = z.object({
  id: z.string().min(1),
});
