import { prisma } from '../src/prisma';

async function main() {
  const m = await prisma.master.create({ data: { name: 'Ирина' } });
  const s = await prisma.service.create({ data: { title: 'Маникюр', priceCents: 3000, durationMin: 60 } });
  console.log('Seeded master:', m);
  console.log('Seeded service:', s);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });