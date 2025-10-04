import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  // Basic seed: services and a master
  const haircut = await prisma.service.upsert({
    where: { name: "Haircut" },
    update: {},
    create: { name: "Haircut", description: "Standard haircut", price: 1500, durationMin: 30 }
  });

  const coloring = await prisma.service.upsert({
    where: { name: "Coloring" },
    update: {},
    create: { name: "Coloring", description: "Hair coloring", price: 3500, durationMin: 90 }
  });

  const master = await prisma.master.upsert({
    where: { id: "11111111-1111-1111-1111-111111111111" },
    update: {},
    create: { id: "11111111-1111-1111-1111-111111111111", name: "Анна", specialties: ["haircut", "coloring"] }
  });

  console.log({ haircut, coloring, master });
}

main().finally(async () => prisma.$disconnect());