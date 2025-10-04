import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  // ensure some services
  const servicesData = [
    { name: "Стрижка", description: "Классическая стрижка", price: 1500, durationMin: 60 },
    { name: "Маникюр", description: "Гигиенический маникюр", price: 1200, durationMin: 60 },
    { name: "Окрашивание", description: "Окрашивание волос", price: 3500, durationMin: 120 },
  ];

  const serviceIds: string[] = [];
  for (const s of servicesData) {
    const existing = await prisma.service.findFirst({ where: { name: s.name } });
    if (existing) {
      serviceIds.push(existing.id);
    } else {
      const created = await prisma.service.create({ data: s });
      serviceIds.push(created.id);
    }
  }

  // ensure masters
  const mastersData = [
    { name: "Анна", phone: "+79990001122", description: "Стилист" },
    { name: "Мария", phone: "+79990003344", description: "Мастер ногтевого сервиса" },
  ];

  const masterIds: string[] = [];
  for (const m of mastersData) {
    const existing = await prisma.master.findFirst({ where: { name: m.name } });
    if (existing) {
      masterIds.push(existing.id);
    } else {
      const created = await prisma.master.create({ data: m });
      masterIds.push(created.id);
    }
  }

  // ensure clients
  const clientsData = [
    { name: "Иван", phone: "+79998887766" },
    { name: "Ольга", phone: "+79997776655" },
  ];

  const clientIds: string[] = [];
  for (const c of clientsData) {
    const existing = await prisma.client.findFirst({ where: { phone: c.phone } });
    if (existing) {
      clientIds.push(existing.id);
    } else {
      const created = await prisma.client.create({ data: c });
      clientIds.push(created.id);
    }
  }

  // link first master to first two services using unique composite key
  const msPairs = [
    { masterId: masterIds[0], serviceId: serviceIds[0] },
    { masterId: masterIds[0], serviceId: serviceIds[1] },
  ];

  for (const pair of msPairs) {
    await prisma.masterService.upsert({
      where: { masterId_serviceId_unique: pair },
      update: {},
      create: pair,
    });
  }

  console.log("Seed completed.");
}

main().finally(async () => {
  await prisma.$disconnect();
});
