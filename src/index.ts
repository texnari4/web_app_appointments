import express from "express";
import path from "path";
import { PrismaClient, AppointmentStatus } from "@prisma/client";
import tgRouter from "./telegram"; // assume existing telegram router
// If cors is installed, use it; otherwise skip to avoid runtime crash
let maybeCors: any = null;
try { maybeCors = require("cors"); } catch {}

const prisma = new PrismaClient();
const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
if (maybeCors) {
  app.use(maybeCors());
}

// __dirname is available because we compile to CommonJS. No import.meta here.
const ROOT_DIR = path.resolve(__dirname, "..");
const PUBLIC_DIR = path.join(ROOT_DIR, "public");
const ADMIN_DIR = path.join(PUBLIC_DIR, "admin");

// Static files (admin UI and others)
app.use(express.static(PUBLIC_DIR));

// Home page: simple index with available endpoints
app.get("/", (_req, res) => {
  res.type("html").send(`
    <h1>Онлайн‑запись</h1>
    <p>Сервер: Express + Prisma</p>
    <ul>
      <li>GET /api/services</li>
      <li>POST /api/appointments</li>
      <li>GET /admin/api/services</li>
      <li>POST /admin/api/services</li>
      <li>PUT /admin/api/services/:id</li>
      <li>DELETE /admin/api/services/:id</li>
    </ul>
  `);
});

/* ========= PUBLIC API ========= */

// Список услуг
app.get("/api/services", async (_req, res) => {
  try {
    const services = await prisma.service.findMany({
      orderBy: { name: "asc" }
    });
    res.json(services);
  } catch (err: any) {
    console.error("[api/services] error", err);
    res.status(500).json({ error: "failed_to_list_services" });
  }
});

// Создание записи
app.post("/api/appointments", async (req, res) => {
  try {
    const { serviceId, staffId, locationId, startAtISO, durationMin, client } = req.body || {};

    if (!serviceId || !staffId || !locationId) {
      return res.status(400).json({ error: "serviceId, staffId, locationId are required" });
    }
    if (!startAtISO || !durationMin) {
      return res.status(400).json({ error: "startAtISO and durationMin are required" });
    }

    const startAt = new Date(startAtISO);
    const endAt = new Date(startAt.getTime() + Number(durationMin) * 60000);

    // client can be { id } to connect by existing client id, or minimal data to create
    let clientConnectOrCreate: any = undefined;
    if (client?.id) {
      clientConnectOrCreate = { connect: { id: String(client.id) } };
    } else if (client?.tgUserId) {
      // Try connect by tgUserId or create a minimal client
      const existing = await prisma.client.findUnique({ where: { tgUserId: String(client.tgUserId) } });
      if (existing) {
        clientConnectOrCreate = { connect: { id: existing.id } };
      } else {
        clientConnectOrCreate = {
          create: {
            tgUserId: String(client.tgUserId),
            firstName: client.firstName || "—",
            lastName: client.lastName || "—",
            // emailEnc/phoneEnc optional in schema; only set if present in request
            ...(client.emailEnc ? { emailEnc: String(client.emailEnc) } : {}),
            ...(client.phoneEnc ? { phoneEnc: String(client.phoneEnc) } : {}),
          }
        };
      }
    }

    const created = await prisma.appointment.create({
      data: {
        startAt,
        endAt,
        status: AppointmentStatus.CREATED,
        service: { connect: { id: String(serviceId) } },
        staff:   { connect: { id: String(staffId) } },
        location:{ connect: { id: String(locationId) } },
        ...(clientConnectOrCreate ? { client: clientConnectOrCreate } : {}),
      },
      include: {
        service: true,
        staff: true,
        location: true,
        client: true,
      }
    });

    res.status(201).json(created);
  } catch (err: any) {
    console.error("[api/appointments] error", err);
    res.status(500).json({ error: "failed_to_create_appointment", detail: err?.message });
  }
});

/* ========= ADMIN API (Services CRUD) ========= */
const adminApi = express.Router();

function checkAdminKey(req: express.Request, res: express.Response): boolean {
  const requiredKey = process.env.ADMIN_KEY;
  if (!requiredKey) return true;
  const provided = req.header("X-Admin-Key");
  if (provided !== requiredKey) {
    res.status(401).json({ error: "unauthorized" });
    return false;
  }
  return true;
}

adminApi.get("/services", async (req, res) => {
  if (!checkAdminKey(req, res)) return;
  try {
    const items = await prisma.service.findMany({ orderBy: { createdAt: "desc" } });
    res.json(items);
  } catch (e: any) {
    console.error("[admin] list services", e);
    res.status(500).json({ error: "list_failed", detail: e?.message });
  }
});

adminApi.post("/services", async (req, res) => {
  if (!checkAdminKey(req, res)) return;
  try {
    const { name, priceCents, durationMin } = req.body || {};
    if (!name || priceCents == null || durationMin == null) {
      return res.status(400).json({ error: "name, priceCents, durationMin required" });
    }
    const created = await prisma.service.create({
      data: {
        name: String(name),
        priceCents: Number(priceCents),
        durationMin: Number(durationMin),
      }
    });
    res.status(201).json(created);
  } catch (e: any) {
    console.error("[admin] create service", e);
    res.status(500).json({ error: "create_failed", detail: e?.message });
  }
});

adminApi.put("/services/:id", async (req, res) => {
  if (!checkAdminKey(req, res)) return;
  try {
    const { id } = req.params;
    const { name, priceCents, durationMin } = req.body || {};
    const updated = await prisma.service.update({
      where: { id: String(id) },
      data: {
        ...(name != null ? { name: String(name) } : {}),
        ...(priceCents != null ? { priceCents: Number(priceCents) } : {}),
        ...(durationMin != null ? { durationMin: Number(durationMin) } : {}),
      }
    });
    res.json(updated);
  } catch (e: any) {
    console.error("[admin] update service", e);
    res.status(500).json({ error: "update_failed", detail: e?.message });
  }
});

adminApi.delete("/services/:id", async (req, res) => {
  if (!checkAdminKey(req, res)) return;
  try {
    const { id } = req.params;
    await prisma.service.delete({ where: { id: String(id) } });
    res.json({ ok: true });
  } catch (e: any) {
    console.error("[admin] delete service", e);
    res.status(500).json({ error: "delete_failed", detail: e?.message });
  }
});

app.use("/admin/api", adminApi);

// Admin page route (serve static HTML)
app.get("/admin/services", (_req, res) => {
  const filePath = path.join(ADMIN_DIR, "services.html");
  res.sendFile(filePath);
});

// Telegram webhook/router (keep mounted if present)
app.use("/tg", tgRouter);

// Start server
const PORT = Number(process.env.PORT || 3000);
app.listen(PORT, async () => {
  console.log(`[http] listening on :${PORT}`);
  try {
    // Attempt a simple query to init Prisma
    await prisma.$queryRaw`SELECT 1`;
  } catch {}
});
