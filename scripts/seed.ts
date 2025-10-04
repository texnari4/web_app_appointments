import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function ensureService(name: string, price: number, durationMinutes: number, description?: string) {
  // name не уникален — ищем первый, иначе создаём
  const existed = await prisma.service.findFirst({ where: { name } });
  if (existed) return existed;
  return prisma.service.create({ data: { name, price, durationMinutes, description } });
}

async function ensureMaster(name: string, specialty?: string) {
  const existed = await prisma.master.findFirst({ where: { name } });
  if (existed) return existed;
  return prisma.master.create({ data: { name, specialty } });
}

async function ensureClient(name: string, phone?: string) {
  const existed = await prisma.client.findFirst({ where: { name, phone } });
  if (existed) return existed;
  return prisma.client.create({ data: { name, phone } });
}

async function main() {
  const haircut = await ensureService('Стрижка', 1500, 60, 'Классическая стрижка');
  const manicure = await ensureService('Маникюр', 1200, 60, 'Маникюр с покрытием');
  const coloring = await ensureService('Окрашивание', 3500, 120, 'Окрашивание волос');

  const anna = await ensureMaster('Анна', 'Парикмахер');
  const olga = await ensureMaster('Ольга', 'Мастер маникюра');

  // Привязка услуг мастеров (через MasterService) — создаём если нет
  const pairs: Array<[string, string]> = [
    [anna.id, haircut.id],
    [anna.id, coloring.id],
    [olga.id, manicure.id]
  ];
  for (const [masterId, serviceId] of pairs) {
    await prisma.masterService.upsert({
      where: { masterId_serviceId: { masterId, serviceId } },
      update: {},
      create: { masterId, serviceId }
    });
  }

  // Тестовый клиент
  const ivan = await ensureClient('Иван Петров', '+79990000000');

  console.log('Seed completed:', { services: [haircut.name, manicure.name, coloring.name], masters: [anna.name, olga.name], client: ivan.name });
}

main().finally(async () => { await prisma.$disconnect(); });