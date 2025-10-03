import express from "express";
import path from "path";
import { prisma } from "./prisma";
import { handleTelegramWebhook, installWebhookIfNeeded } from "./telegram";

const app = express();
app.use(express.json());

// Health
app.get("/health", (_req, res) => res.json({ ok: true }));

// Simple REST to verify Prisma
app.get("/api/services", async (_req, res) => {
  const list = await prisma.service.findMany({ orderBy: { name: "asc" } });
  res.json(list);
});

app.post("/api/appointments", async (req, res) => {
  try {
    const { locationId, serviceId, staffId, client } = req.body || {};
    const now = new Date();
    const end = new Date(now.getTime() + 60 * 60 * 1000);

    const clientRec = await prisma.client.create({
      data: {
        firstName: client?.firstName ?? "Client"
      }
    });

    const created = await prisma.appointment.create({
      data: {
        locationId,
        serviceId,
        staffId,
        clientId: clientRec.id,
        startAt: now,
        endAt: end
      },
      include: { service: true, staff: true, location: true, client: true }
    });

    res.status(201).json(created);
  } catch (e: any) {
    console.error("[api] create appointment error:", e);
    res.status(400).json({ error: "Bad request" });
  }
});

// Telegram webhook endpoint
app.post("/tg/webhook", handleTelegramWebhook);

// Static miniapp
const publicDir = path.resolve(__dirname, "..", "public");
app.use(express.static(publicDir));
app.get("/", (_req, res) => {
  res.sendFile(path.join(publicDir, "index.html"));
});

const port = process.env.PORT || 3000;

app.listen(port, async () => {
  console.log(`Server listening on :${port}`);
  await installWebhookIfNeeded();
});
