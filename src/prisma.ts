import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient();

export async function ensureDb() {
  // simple ping
  await prisma.$queryRaw`SELECT 1`;
}
