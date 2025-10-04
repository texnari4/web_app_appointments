import { z } from 'zod'

export const setMetaSchema = z.object({
  key: z.string().min(1),
  value: z.string().nullable().optional()
})