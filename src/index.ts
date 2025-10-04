import express, { Request, Response } from "express";
import cors from "cors";
import pino from "pino";
import pinoHttp from "pino-http";
import { PrismaClient } from "@prisma/client";
import {
  serviceCreateSchema,
  serviceUpdateSchema,
  appointmentCreateSchema,
} from "./validators.js";

const logger = pino();
const app = express();
const prisma = new PrismaClient();
const PORT = Number(process.env.PORT || 8080);

app.use(cors());
app.use(express.json());
app.use(pinoHttp({ logger }));

app.get("/health", (_req: Request, res: Response) => {
  res.json({ ok: true });
});

// ==== Services CRUD ====
app.get("/api/services", async (_req: Request, res: Response) => {
  const items = await prisma.service.findMany({ orderBy: { createdAt: "desc" } });
  res.json(items);
});

app.post("/api/services", async (req: Request, res: Response) => {
  const parse = serviceCreateSchema.safeParse(req.body);
  if (!parse.success) return res.status(400).json({ error: parse.error.flatten() });
  const created = await prisma.service.create({ data: parse.data });
  res.status(201).json(created);
});

app.patch("/api/services/:id", async (req: Request, res: Response) => {
  const { id } = req.params;
  const parse = serviceUpdateSchema.safeParse(req.body);
  if (!parse.success) return res.status(400).json({ error: parse.error.flatten() });
  const updated = await prisma.service.update({ where: { id }, data: parse.data });
  res.json(updated);
});

app.delete("/api/services/:id", async (req: Request, res: Response) => {
  const { id } = req.params;
  await prisma.service.delete({ where: { id } });
  res.status(204).send();
});

// ==== Create appointment ====
app.post("/api/appointments", async (req: Request, res: Response) => {
  const parse = appointmentCreateSchema.safeParse(req.body);
  if (!parse.success) return res.status(400).json({ error: parse.error.flatten() });
  const { clientId, masterId, serviceId, startsAt, note } = parse.data;

  const service = await prisma.service.findUnique({ where: { id: serviceId } });
  if (!service) return res.status(400).json({ error: "Service not found" });

  const start = new Date(startsAt);
  const ends = new Date(start.getTime() + service.durationMin * 60_000);

  const created = await prisma.appointment.create({
    data: {
      clientId,
      masterId,
      serviceId,
      startsAt: start,
      endsAt: ends,
      note,
    },
  });
  res.status(201).json(created);
});

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
