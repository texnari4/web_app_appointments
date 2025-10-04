import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient({
  log: [
    { level: 'query', emit: 'event' },
    { level: 'error', emit: 'stdout' },
    { level: 'warn', emit: 'stdout' },
  ],
});

prisma.$on('query', (e: any) => {
  // Keep it light in prod; Railway logs can get noisy
  // console.log('Query:', e.query, e.params, `${e.duration}ms`);
});
