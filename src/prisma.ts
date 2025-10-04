import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient();

export async function ensureDbConnection() {
  // simple warm-up query
  await prisma.$queryRaw`SELECT 1`;
}