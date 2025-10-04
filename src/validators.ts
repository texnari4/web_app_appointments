import { z } from "zod";

export const masterCreateSchema = z.object({
  name: z.string().min(1, "Введите имя"),
  phone: z.string().min(3).optional().or(z.literal("").transform(() => undefined)),
  about: z.string().max(500).optional().or(z.literal("").transform(() => undefined)),
  active: z.boolean().optional().default(true)
});

export type MasterCreateInput = z.infer<typeof masterCreateSchema>;
