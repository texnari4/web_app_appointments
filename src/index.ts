import express from "express";
import path from "path";
import cors from "cors";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const app = express();

// Middleware
app.use(express.json());
app.use(cors());

// Static
app.use("/public", express.static(path.join(__dirname, "..", "public")));

// Optional Telegram router: mounted only if file exists/exports router
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const tg = require("./telegram");
  if (tg?.tgRouter) {
    app.use("/tg", tg.tgRouter);
  }
} catch (e) {
  // ignore if there's no telegram module
}

// Root page
app.get("/", (_req, res) => {
  res.type("text/plain").send([
    "Онлайн‑запись",
    "Сервер: Express + Prisma",
    "",
    "GET /api/services",
    "POST /api/appointments",
    "GET /admin/services",
    "GET /admin/api/services",
    "POST /admin/api/services",
    "PUT /admin/api/services/:id",
    "DELETE /admin/api/services/:id",
  ].join("\n"));
});

/** SERVICES (public) */
app.get("/api/services", async (_req, res) => {
  try {
    const items = await prisma.service.findMany({
      orderBy: { createdAt: "asc" },
      select: { id: true, name: true, durationMin: true, priceCents: true },
    });
    res.json(items);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch services" });
  }
});

/** APPOINTMENTS (public create) */
app.post("/api/appointments", async (req, res) => {
  try {
    const { serviceId, staffId, startAtISO, durationMin, client } = req.body ?? {};

    if (!serviceId || !startAtISO || !durationMin) {
      return res.status(400).json({ error: "serviceId, startAtISO, durationMin are required" });
    }
    const startAt = new Date(startAtISO);
    if (isNaN(startAt.getTime())) {
      return res.status(400).json({ error: "startAtISO is invalid datetime" });
    }
    const endAt = new Date(startAt.getTime() + Number(durationMin) * 60 * 1000);

    // Ensure service exists
    const service = await prisma.service.findUnique({ where: { id: serviceId } });
    if (!service) return res.status(404).json({ error: "service not found" });

    // Resolve client (support by id OR by tgUserId but tgUserId may be non-unique in Prisma schema types)
    let clientConnect: { id: string } | undefined = undefined;
    if (client?.id) {
      const c = await prisma.client.findUnique({ where: { id: client.id } });
      if (!c) return res.status(404).json({ error: "client not found" });
      clientConnect = { id: c.id };
    } else if (client?.tgUserId) {
      // Use findFirst instead of whereUnique to avoid TS error when tgUserId is not unique in schema
      const existing = await prisma.client.findFirst({ where: { tgUserId: String(client.tgUserId) } });
      const ensured = existing ?? await prisma.client.create({
        data: {
          tgUserId: String(client.tgUserId),
          name: client.name ?? null,
        },
      });
      clientConnect = { id: ensured.id };
    }

    // Build create data; include only relations that exist in schema
    const data: any = {
      startAt,
      endAt,
      status: "CREATED",
      service: { connect: { id: service.id } },
    };
    if (clientConnect) data.client = { connect: clientConnect };
    if (staffId) data.staff = { connect: { id: staffId } }; // will work only if Staff relation exists

    const created = await prisma.appointment.create({
      data,
      include: {
        service: true,
        client: true,
        staff: true,
      },
    });
    res.status(201).json(created);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to create appointment" });
  }
});

/** ADMIN PAGE */
app.get("/admin/services", (_req, res) => {
  res.sendFile(path.join(__dirname, "..", "public", "admin", "services.html"));
});

/** ADMIN API (simple key check via header X-Admin-Key = ADMIN_KEY env) */
function checkAdmin(req: express.Request, res: express.Response): boolean {
  const reqKey = req.header("X-Admin-Key") ?? "";
  const admKey = process.env.ADMIN_KEY ?? "";
  if (admKey && reqKey !== admKey) {
    res.status(401).json({ error: "unauthorized" });
    return false;
  }
  return true;
}

app.get("/admin/api/services", async (req, res) => {
  if (!checkAdmin(req, res)) return;
  try {
    const items = await prisma.service.findMany({
      orderBy: { createdAt: "asc" },
      select: { id: true, name: true, durationMin: true, priceCents: true },
    });
    res.json(items);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch services" });
  }
});

app.post("/admin/api/services", async (req, res) => {
  if (!checkAdmin(req, res)) return;
  try {
    const { name, durationMin, priceCents } = req.body ?? {};
    if (!name || durationMin == null || priceCents == null) {
      return res.status(400).json({ error: "name, durationMin, priceCents are required" });
    }
    const created = await prisma.service.create({
      data: { name: String(name), durationMin: Number(durationMin), priceCents: Number(priceCents) },
      select: { id: true, name: true, durationMin: true, priceCents: true },
    });
    res.status(201).json(created);
  } catch (err) {
    res.status(500).json({ error: "Failed to create service" });
  }
});

app.put("/admin/api/services/:id", async (req, res) => {
  if (!checkAdmin(req, res)) return;
  try {
    const { id } = req.params;
    const { name, durationMin, priceCents } = req.body ?? {};
    const updated = await prisma.service.update({
      where: { id },
      data: {
        ...(name != null ? { name: String(name) } : {}),
        ...(durationMin != null ? { durationMin: Number(durationMin) } : {}),
        ...(priceCents != null ? { priceCents: Number(priceCents) } : {}),
      },
      select: { id: true, name: true, durationMin: true, priceCents: true },
    });
    res.json(updated);
  } catch (err) {
    res.status(500).json({ error: "Failed to update service" });
  }
});

app.delete("/admin/api/services/:id", async (req, res) => {
  if (!checkAdmin(req, res)) return;
  try {
    const { id } = req.params;
    await prisma.service.delete({ where: { id } });
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: "Failed to delete service" });
  }
});

// Start server
const PORT = Number(process.env.PORT || 3000);
app.listen(PORT, () => {
  console.log(`Server listening on :${PORT}`);
});