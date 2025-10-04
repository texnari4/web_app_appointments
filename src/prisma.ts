import { PrismaClient } from '@prisma/client'

declare global {
  // allow global `var` declarations
  // eslint-disable-next-line no-var
  var __prisma: PrismaClient | undefined
}

export const prisma =
  global.__prisma ??
  new PrismaClient({
    log: ['warn', 'error']
  })

if (process.env.NODE_ENV !== 'production') {
  global.__prisma = prisma
}