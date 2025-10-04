import { z } from 'zod';

// Schema for creating a service. Price is expressed in minor currency units (e.g. cents).
export const serviceSchema = z.object({
  name: z.string().min(1, { message: 'Name is required' }),
  price: z.number().int().min(0, { message: 'Price must be a non-negative integer' }),
  durationMin: z.number().int().positive({ message: 'Duration must be greater than zero' }),
  masterId: z.string().cuid().optional(),
});

// Schema for creating a master.
export const masterSchema = z.object({
  name: z.string().min(1, { message: 'Name is required' }),
  phone: z.string().min(3, { message: 'Phone is required' }),
  email: z.string().email().optional(),
});
