// Example seed (run with ts-node or compile first)
import prisma from '../src/prisma.js';
async function main(){
  const names = ['Анна','Мария','Елена'];
  for (const name of names){
    await prisma.master.upsert({ where: { name }, update: {}, create: { name } });
  }
  console.log('Seed done');
  await prisma.$disconnect();
}
main().catch(async e=>{ console.error(e); await prisma.$disconnect(); process.exit(1); });
