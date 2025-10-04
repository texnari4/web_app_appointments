import { prisma } from "../src/prisma";

async function main() {
  const count = await prisma.master.count();
  if (count > 0) {
    console.log("Masters already seeded:", count);
    return;
  }
  await prisma.master.createMany({
    data: [
      { name: "Анна", phone: "+7 900 000-00-01", bio: "Брови / ресницы" },
      { name: "Мария", phone: "+7 900 000-00-02", bio: "Маникюр / педикюр" },
    ]
  });
  console.log("Seed complete");
}
main().finally(()=>process.exit(0));
