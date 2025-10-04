
import { prisma } from '../src/prisma';

async function main() {
  const m1 = await prisma.master.create({ data: { name: 'Alice', phone: '+1000000001' } });
  const m2 = await prisma.master.create({ data: { name: 'Bob', phone: '+1000000002' } });

  const s1 = await prisma.service.create({ data: { name: 'Haircut', price: 2000, durationMins: 45 } });
  const s2 = await prisma.service.create({ data: { name: 'Manicure', price: 2500, durationMins: 60 } });

  await prisma.master.update({ where: { id: m1.id }, data: { services: { connect: [{ id: s1.id }, { id: s2.id }] } } });
  await prisma.master.update({ where: { id: m2.id }, data: { services: { connect: [{ id: s2.id }] } } });

  await prisma.appointment.create({
    data: {
      masterId: m1.id,
      serviceId: s1.id,
      customerName: 'Test Customer',
      customerPhone: '+1999999999',
      startsAt: new Date(Date.now() + 3600 * 1000),
    },
  });

  console.log('Seeded');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
}).finally(async () => {
  await prisma.$disconnect();
});
