import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient();

export async function ensureDb() {
  await prisma.$queryRaw`SELECT 1`; // fail fast if DB is unreachable
}
