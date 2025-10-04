import { prisma } from '../src/prisma';

async function main() {
  await prisma.master.createMany({
    data: [
      { name: 'Анна', phone: '+79990000001', bio: 'Ногтевой сервис' },
      { name: 'Мария', phone: '+79990000002', bio: 'Брови/ресницы' },
    ]
  });
  console.log('seeded');
}

main().finally(()=> prisma.$disconnect());
