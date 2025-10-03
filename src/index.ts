import express, { Request, Response } from "express";
import cors from "cors";
import { PrismaClient, AppointmentStatus } from "@prisma/client";
import { installWebhook, tgRouter } from "./telegram";

const app = express();
app.use(express.json());
app.use(cors());

const prisma = new PrismaClient();

// Health
app.get("/health", (_req, res) => res.json({ ok: true }));

// Public: list services
app.get("/api/services", async (_req: Request, res: Response) => {
  try {
    const services = await prisma.service.findMany({
      orderBy: { createdAt: "asc" },
      select: {
        id: true,
        name: true,
        description: true,
        durationMin: true,
        priceCents: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    res.json({ status: "ok", data: services });
  } catch (e: any) {
    console.error("[api/services] error", e);
    res.status(500).json({ status: "error", message: e?.message || "failed" });
  }
});

// Create appointment
app.post("/api/appointments", async (req: Request, res: Response) => {
  try {
    const {
      serviceId,
      staffId,
      locationId,
      startAt,
      endAt,
      tgUserId,
      firstName,
      lastName,
      // phone/email intentionally NOT persisted unless your schema has phoneEnc/emailEnc
    } = req.body || {};

    if (!serviceId || !staffId || !locationId) {
      return res.status(400).json({
        status: "error",
        message: "serviceId, staffId, locationId are required",
      });
    }
    if (!startAt || !endAt) {
      return res.status(400).json({
        status: "error",
        message: "startAt and endAt are required",
      });
    }

    let clientId: string | undefined;

    if (tgUserId) {
      // Find by tgUserId (non-unique in older DBs, so use findFirst)
      const existing = await prisma.client.findFirst({ where: { tgUserId: String(tgUserId) } });
      if (existing) {
        clientId = existing.id;
      } else {
        const created = await prisma.client.create({
          data: {
            tgUserId: String(tgUserId),
            firstName: firstName ? String(firstName) : null,
            lastName: lastName ? String(lastName) : null,
          },
          select: { id: true },
        });
        clientId = created.id;
      }
    }

    const createdAppt = await prisma.appointment.create({
      data: {
        startAt: new Date(startAt),
        endAt: new Date(endAt),
        status: AppointmentStatus.CREATED,
        service: { connect: { id: serviceId } },
        staff: { connect: { id: staffId } },
        location: { connect: { id: locationId } },
        ...(clientId ? { client: { connect: { id: clientId } } } : {}),
      },
      include: {
        service: true,
        staff: true,
        location: true,
        client: true,
      },
    });

    res.json({ status: "ok", data: createdAppt });
  } catch (e: any) {
    console.error("[api/appointments] error", e);
    res.status(500).json({ status: "error", message: e?.message || "failed" });
  }
});

// --- Admin: minimal services editor API (JSON-only for now) ---
app.get("/admin/api/services", async (_req, res) => {
  try {
    const list = await prisma.service.findMany({
      orderBy: { createdAt: "asc" },
    });
    res.json({ status: "ok", data: list });
  } catch (e: any) {
    console.error("[admin/services:list] error", e);
    res.status(500).json({ status: "error", message: e?.message || "failed" });
  }
});

app.post("/admin/api/services", async (req, res) => {
  try {
    const { name, description, durationMin, priceCents } = req.body || {};
    if (!name || !durationMin || !priceCents) {
      return res.status(400).json({ status: "error", message: "name, durationMin, priceCents are required" });
    }
    const created = await prisma.service.create({
      data: {
        name: String(name),
        description: description ? String(description) : null,
        durationMin: Number(durationMin),
        priceCents: Number(priceCents),
      },
    });
    res.json({ status: "ok", data: created });
  } catch (e: any) {
    console.error("[admin/services:create] error", e);
    res.status(500).json({ status: "error", message: e?.message || "failed" });
  }
});

app.put("/admin/api/services/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, durationMin, priceCents } = req.body || {};
    const updated = await prisma.service.update({
      where: { id },
      data: {
        ...(name !== undefined ? { name: String(name) } : {}),
        ...(description !== undefined ? { description: description ? String(description) : null } : {}),
        ...(durationMin !== undefined ? { durationMin: Number(durationMin) } : {}),
        ...(priceCents !== undefined ? { priceCents: Number(priceCents) } : {}),
      },
    });
    res.json({ status: "ok", data: updated });
  } catch (e: any) {
    console.error("[admin/services:update] error", e);
    res.status(500).json({ status: "error", message: e?.message || "failed" });
  }
});

app.delete("/admin/api/services/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const deleted = await prisma.service.delete({ where: { id } });
    res.json({ status: "ok", data: deleted });
  } catch (e: any) {
    console.error("[admin/services:delete] error", e);
    res.status(500).json({ status: "error", message: e?.message || "failed" });
  }
});

// --- Static info page & basic admin HTML placeholder ---
app.get("/", (_req, res) => {
  res.type("html").send(`
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;padding:24px;max-width:720px;margin:0 auto;line-height:1.5}
      code{background:#f5f5f7;padding:2px 6px;border-radius:6px}
      a{color:#007aff;text-decoration:none}
      .muted{color:#6e6e73}
    </style>
    <h1>Онлайн‑запись</h1>
    <p class="muted">Express + Prisma. Эндпоинты:</p>
    <ul>
      <li><code>GET /api/services</code></li>
      <li><code>POST /api/appointments</code></li>
      <li><code>GET /admin/api/services</code></li>
      <li><code>POST /admin/api/services</code></li>
    </ul>
    <p class="muted">Telegram webhook: <code>/tg/webhook</code></p>
  `);
});

// Telegram router
app.use("/tg", tgRouter);

// Boot
const PORT = Number(process.env.PORT || 8080);
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || "").trim();
const TG_BOT_TOKEN = (process.env.TG_BOT_TOKEN || "").trim();

app.listen(PORT, async () => {
  console.log(`[http] listening on :${PORT}`);
  try {
    await installWebhook(app, PUBLIC_BASE_URL, TG_BOT_TOKEN);
  } catch (e) {
    console.error("[tg] setWebhook failed", e);
  }
});
