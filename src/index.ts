import express from "express";
import cors from "cors";
import pino from "pino";
import pinoHttp from "pino-http";
import path from "path";
import { prisma, healthCheckDb } from "./prisma";
import { MasterCreateSchema, MasterUpdateSchema, IdParamSchema } from "./validators";

const PORT = parseInt(process.env.PORT || "8080", 10);
const app = express();
const logger = pino({ level: process.env.LOG_LEVEL || "info" });

app.use(pinoHttp({ logger }));
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Static
app.use("/", express.static(path.join(process.cwd(), "public")));
app.use("/admin", express.static(path.join(process.cwd(), "public", "admin")));

// Health
app.get("/health", async (req, res) => {
  const dbOk = await healthCheckDb();
  res.json({ ok: true, ts: new Date().toISOString(), db: dbOk });
});

// Masters API
app.get("/api/masters", async (_req, res) => {
  const items = await prisma.master.findMany({ orderBy: { createdAt: "desc" } });
  res.json({ ok: true, data: items });
});
app.get("/public/api/masters", async (req, res) => app._router.handle(req, res)); // alias via same router

app.post("/api/masters", async (req, res) => {
  const parsed = MasterCreateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ ok: false, error: parsed.error.flatten() });
  const created = await prisma.master.create({ data: parsed.data });
  res.status(201).json({ ok: true, data: created });
});

app.get("/api/masters/:id", async (req, res) => {
  const p = IdParamSchema.safeParse(req.params);
  if (!p.success) return res.status(400).json({ ok: false, error: p.error.flatten() });
  const item = await prisma.master.findUnique({ where: { id: p.data.id } });
  if (!item) return res.status(404).json({ ok: false, error: "not found" });
  res.json({ ok: true, data: item });
});

app.put("/api/masters/:id", async (req, res) => {
  const p = IdParamSchema.safeParse(req.params);
  if (!p.success) return res.status(400).json({ ok: false, error: p.error.flatten() });
  const body = MasterUpdateSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.flatten() });
  try {
    const updated = await prisma.master.update({ where: { id: p.data.id }, data: body.data });
    res.json({ ok: true, data: updated });
  } catch (e) {
    res.status(404).json({ ok: false, error: "not found" });
  }
});

app.delete("/api/masters/:id", async (req, res) => {
  const p = IdParamSchema.safeParse(req.params);
  if (!p.success) return res.status(400).json({ ok: false, error: p.error.flatten() });
  try {
    const deleted = await prisma.master.delete({ where: { id: p.data.id } });
    res.json({ ok: true, data: deleted });
  } catch (e) {
    res.status(404).json({ ok: false, error: "not found" });
  }
});

// Fallback 404 JSON for API, and index.html for others
app.use((req, res, next) => {
  if (req.path.startsWith("/api/")) return res.status(404).json({ ok: false, error: "not found" });
  next();
});

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
