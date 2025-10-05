
import express, { Request, Response } from "express";
import path from "node:path";
import pinoHttp from "pino-http";
import cors from "cors";
import { z } from "zod";
import { addMaster, listMasters, listAppointments, createAppointment, updateAppointment } from "./db.js";

const app = express();
const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;

// logging
const logger = pinoHttp();

app.use(logger);
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// static
const publicDir = path.resolve(process.cwd(), "public");
app.use("/public", express.static(publicDir, { etag: false, lastModified: false, maxAge: 0 }));

// health
app.get("/health", (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

// --- Masters API (unchanged contract) ---
app.get(["/public/api/masters","/api/masters"], async (_req, res) => {
  try {
    const items = await listMasters();
    res.set("Cache-Control","no-store").json({ items });
  } catch (e) {
    res.status(500).json({ error: "INTERNAL_ERROR" });
  }
});

const masterCreateSchema = z.object({
  name: z.string().min(1),
  phone: z.string().min(3),
  avatarUrl: z.string().url().optional(),
  isActive: z.boolean().optional().default(true)
});

app.post(["/public/api/masters","/api/masters"], async (req, res) => {
  const parse = masterCreateSchema.safeParse(req.body);
  if (!parse.success) return res.status(400).json({ error: "VALIDATION_ERROR", details: parse.error.flatten() });
  try {
    const created = await addMaster({
      name: parse.data.name,
      phone: parse.data.phone,
      avatarUrl: parse.data.avatarUrl,
      isActive: parse.data.isActive
    });
    res.status(201).json(created);
  } catch (e) {
    res.status(500).json({ error: "INTERNAL_ERROR" });
  }
});

// --- Appointments API ---
const querySchema = z.object({
  masterId: z.string().optional(),
  from: z.string().optional(),
  to: z.string().optional(),
});

app.get("/public/api/appointments", async (req, res) => {
  const q = querySchema.safeParse(req.query);
  if (!q.success) return res.status(400).json({ error: "VALIDATION_ERROR" });
  try {
    const items = await listAppointments({ masterId: q.data.masterId, from: q.data.from, to: q.data.to });
    res.set("Cache-Control","no-store").json({ items });
  } catch {
    res.status(500).json({ error: "INTERNAL_ERROR" });
  }
});

const createSchema = z.object({
  masterId: z.string().min(1),
  customerName: z.string().min(1),
  customerPhone: z.string().min(3),
  service: z.string().optional(),
  notes: z.string().optional(),
  start: z.string().datetime(),
  end: z.string().datetime(),
});

app.post("/public/api/appointments", async (req, res) => {
  const parsed = createSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "VALIDATION_ERROR", details: parsed.error.flatten() });
  try {
    const created = await createAppointment(parsed.data);
    res.status(201).json(created);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : "INTERNAL_ERROR";
    if (msg === "MASTER_NOT_FOUND_OR_INACTIVE") return res.status(400).json({ error: msg });
    if (msg === "TIME_CONFLICT") return res.status(409).json({ error: msg });
    res.status(500).json({ error: "INTERNAL_ERROR" });
  }
});

const patchSchema = z.object({
  status: z.enum(["scheduled","canceled","completed"]).optional(),
  notes: z.string().optional()
});

app.patch("/public/api/appointments/:id", async (req, res) => {
  const body = patchSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ error: "VALIDATION_ERROR" });
  try {
    const updated = await updateAppointment(req.params.id, body.data);
    res.json(updated);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : "INTERNAL_ERROR";
    if (msg === "NOT_FOUND") return res.status(404).json({ error: "NOT_FOUND" });
    res.status(500).json({ error: "INTERNAL_ERROR" });
  }
});

// --- Admin UI (keep previous design) ---
app.get(["/admin","/admin/"], (_req, res) => {
  res.sendFile(path.join(publicDir, "admin", "index.html"));
});

// Separate lightweight page to test appointments without touching main admin look
app.get("/admin/appointments", (_req, res) => {
  res.sendFile(path.join(publicDir, "admin", "appointments.html"));
});

// root -> 404 JSON
app.get("/", (_req, res) => res.status(404).json({ error: "NOT_FOUND" }));

app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
