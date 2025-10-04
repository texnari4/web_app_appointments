import express from 'express'
import cors from 'cors'
import pino from 'pino-http'
import { z } from 'zod'
import { prisma } from './prisma'
import { setMetaSchema } from './validators'

const app = express()
app.use(cors())
app.use(express.json())
app.use(pino())

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080

app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() })
})

app.get('/meta/:key', async (req, res) => {
  const key = req.params.key
  const row = await prisma.appMeta.findUnique({ where: { key } })
  res.json({ key, value: row?.value ?? null })
})

app.post('/meta', async (req, res) => {
  const parsed = setMetaSchema.safeParse(req.body)
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() })
  }
  const { key, value } = parsed.data
  const row = await prisma.appMeta.upsert({
    where: { key },
    update: { value },
    create: { key, value }
  })
  res.json({ ok: true, row })
})

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`)
})