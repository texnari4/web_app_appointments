import 'dotenv/config';
import { prisma } from '../src/prisma.js';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const file = path.join(__dirname, '../data/test-data.json');
  const raw = await fs.readFile(file, 'utf-8');
  const data = JSON.parse(raw) as {
    services: Array<{name: string; description?: string; priceCents?: number; durationMin: number; isActive?: boolean}>,
    masters?: Array<{name: string; specialties?: string[]; phone?: string}>
  };

  for (const s of data.services) {
    await prisma.service.upsert({
      where: { name: s.name },
      update: s,
      create: s,
    });
  }

  if (data.masters) {
    for (const m of data.masters) {
      await prisma.master.upsert({
        where: { name: m.name },
        update: m,
        create: { name: m.name, specialties: m.specialties ?? [], phone: m.phone },
      });
    }
  }
  console.log('Seed done');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
