import { PrismaClient } from '@prisma/client'
const prisma = new PrismaClient()

async function main() {
  await prisma.appMeta.upsert({
    where: { key: 'app:name' },
    update: { value: 'Appointments' },
    create: { key: 'app:name', value: 'Appointments' }
  })
  console.log('Seeded app:name')
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
}).finally(async () => {
  await prisma.$disconnect()
})