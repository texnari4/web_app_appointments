import { prisma } from '../src/prisma';

async function main() {
  const master = await prisma.master.create({ data: { name: 'Default Master' } });
  const svc = await prisma.service.create({ data: { title: 'Haircut', priceCents: 2000, durationMin: 30, masterId: master.id } });
  await prisma.appointment.create({
    data: {
      masterId: master.id,
      serviceId: svc.id,
      startsAt: new Date(Date.now() + 3600_000),
      endsAt: new Date(Date.now() + 5400_000),
      customerName: 'John Doe',
      customerPhone: '+123456789'
    }
  });
  console.log('Seeded');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
}).finally(async () => {
  await prisma.$disconnect();
});
