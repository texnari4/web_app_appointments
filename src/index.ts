import express from "express";
import path from "path";
import { fileURLToPath } from "url";
import { PrismaClient } from "@prisma/client";
import adminRoutes from "./routes/admin.js"; // admin router

const prisma = new PrismaClient();
const app = express();

// middlewares
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// static
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
app.use(express.static(path.join(__dirname, "../public")));

// ===== Public API =====
app.get("/api/services", async (_req, res) => {
  try {
    const services = await prisma.service.findMany({
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        name: true,
        description: true,
        durationMin: true,
        priceCents: true,
      },
    });
    res.json({ ok: true, data: services });
  } catch (e) {
    const err = e && typeof e === "object" && "message" in e ? (e as any).message : "Server error";
    res.status(500).json({ ok: false, message: String(err) });
  }
});

// Admin HTML
app.get("/admin/services", (_req, res) => {
  res.sendFile(path.join(__dirname, "../public/admin/services.html"));
});

// Admin API
app.use("/admin/api", adminRoutes);

// Root index
app.get("/", (_req, res) => {
  res.sendFile(path.join(__dirname, "../public/index.html"));
});

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
app.listen(PORT, () => {
  console.log(`[http] listening on :${PORT}`);
});
