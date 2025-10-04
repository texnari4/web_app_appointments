import express from "express";
import cors from "cors";
import path from "path";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const app = express();

// Middlewares
app.use(cors());
app.use(express.json());
// IMPORTANT: support HTML form posts if someone decides to submit <form> without JS
app.use(express.urlencoded({ extended: true }));

// Static admin assets
const publicDir = path.join(process.cwd(), "public");
app.use(express.static(publicDir));

// --------------------------- Public API ---------------------------

// List services (for client app)
app.get("/api/services", async (_req, res) => {
  try {
    const services = await prisma.service.findMany({
      orderBy: { createdAt: "desc" },
      select: { id: true, name: true, durationMin: true, priceCents: true, createdAt: true, updatedAt: true },
    });
    res.json(services);
  } catch (e: any) {
    console.error("GET /api/services error", e);
    res.status(500).json({ error: "Internal error" });
  }
});

// Create appointment (minimal version)
app.post("/api/appointments", async (req, res) => {
  try {
    const { serviceId, startAtISO, durationMin, staffId, client } = req.body || {};
    if (!serviceId || !startAtISO || !client?.tgUserId) {
      return res.status(400).json({ error: "serviceId, startAtISO and client.tgUserId are required" });
    }

    const startAt = new Date(startAtISO);
    const service = await prisma.service.findUnique({ where: { id: serviceId }, select: { durationMin: true } });
    if (!service) return res.status(404).json({ error: "Service not found" });

    const endAt = new Date(startAt.getTime() + (durationMin ?? service.durationMin) * 60_000);

    // Upsert client by tgUserId ONLY — model doesn't have name/phone
    const upsertedClient = await prisma.client.upsert({
      where: { tgUserId: client.tgUserId },
      update: {},
      create: { tgUserId: client.tgUserId },
      select: { id: true },
    });

    const appt = await prisma.appointment.create({
      data: {
        startAt,
        endAt,
        status: "CREATED",
        client: { connect: { id: upsertedClient.id } },
        // Optional relations are skipped if not provided in schema
        service: { connect: { id: serviceId } },
        ...(staffId ? { staff: { connect: { id: staffId } } } : {}),
      },
      select: {
        id: true, startAt: true, endAt: true, status: true,
        client: { select: { id: true } },
        service: { select: { id: true, name: true } },
        staff: { select: { id: true, name: true } },
      },
    });

    res.status(201).json(appt);
  } catch (e: any) {
    console.error("POST /api/appointments error", e);
    res.status(500).json({ error: "Internal error" });
  }
});

// --------------------------- Admin API ---------------------------

// List services (admin)
app.get("/admin/api/services", async (_req, res) => {
  try {
    const services = await prisma.service.findMany({
      orderBy: { createdAt: "desc" },
      select: { id: true, name: true, durationMin: true, priceCents: true, createdAt: true, updatedAt: true },
    });
    res.json(services);
  } catch (e: any) {
    console.error("GET /admin/api/services error", e);
    res.status(500).json({ error: "Internal error" });
  }
});

// Create service
app.post("/admin/api/services", async (req, res) => {
  try {
    const { name, durationMin, priceCents } = req.body || {};

    // Support both form-urlencoded (strings) and JSON (numbers)
    const _name = (name ?? "").toString().trim();
    const _durationMin = Number(durationMin);
    const _priceCents = Number(priceCents);

    if (!_name || isNaN(_durationMin) || isNaN(_priceCents)) {
      return res.status(400).json({ error: "name, durationMin, priceCents are required" });
    }

    const created = await prisma.service.create({
      data: { name: _name, durationMin: _durationMin, priceCents: _priceCents },
      select: { id: true, name: true, durationMin: true, priceCents: true, createdAt: true, updatedAt: true },
    });
    res.status(201).json(created);
  } catch (e: any) {
    console.error("POST /admin/api/services error", e);
    res.status(500).json({ error: "Internal error" });
  }
});

// Update service
app.put("/admin/api/services/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { name, durationMin, priceCents } = req.body || {};
    const payload: any = {};

    if (name !== undefined) payload.name = String(name).trim();
    if (durationMin !== undefined) payload.durationMin = Number(durationMin);
    if (priceCents !== undefined) payload.priceCents = Number(priceCents);

    const updated = await prisma.service.update({
      where: { id },
      data: payload,
      select: { id: true, name: true, durationMin: true, priceCents: true, createdAt: true, updatedAt: true },
    });
    res.json(updated);
  } catch (e: any) {
    console.error("PUT /admin/api/services/:id error", e);
    res.status(500).json({ error: "Internal error" });
  }
});

// Delete service
app.delete("/admin/api/services/:id", async (req, res) => {
  try {
    const { id } = req.params;
    await prisma.service.delete({ where: { id } });
    res.status(204).end();
  } catch (e: any) {
    console.error("DELETE /admin/api/services/:id error", e);
    res.status(500).json({ error: "Internal error" });
  }
});

// Admin page
app.get("/admin/services", (_req, res) => {
  res.sendFile(path.join(publicDir, "admin", "services.html"));
});

// Root page (status)
app.get("/", (_req, res) => {
  res.type("text").send(`Онлайн‑запись
Сервер: Express + Prisma

GET /api/services
POST /api/appointments
GET /admin/api/services
POST /admin/api/services
PUT /admin/api/services/:id
DELETE /admin/api/services/:id
`);
});

// Start server
const PORT = Number(process.env.PORT || 3000);
app.listen(PORT, () => {
  console.log(`Server started on http://0.0.0.0:${PORT}`);
});
