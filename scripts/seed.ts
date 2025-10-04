import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  // Remove existing data
  await prisma.service.deleteMany();
  await prisma.master.deleteMany();

  // Create a master
  const irina = await prisma.master.create({
    data: {
      name: 'Ирина',
      phone: '+375291234567',
      email: 'irina@example.com',
    },
  });

  // Create services
  await prisma.service.createMany({
    data: [
      {
        name: 'Маникюр',
        price: 3000,
        durationMin: 60,
        masterId: irina.id,
      },
      {
        name: 'Педикюр',
        price: 4000,
        durationMin: 90,
      },
    ],
  });
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
