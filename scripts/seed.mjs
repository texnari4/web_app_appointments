import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const m = await prisma.master.create({ data: { name: 'Ирина' } });
const s = await prisma.service.create({ data: { title: 'Маникюр', priceCents: 3000, durationMin: 60 } });
console.log('Seeded master:', m);
console.log('Seeded service:', s);
process.exit(0);