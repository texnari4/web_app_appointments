import { Router } from "express";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const router = Router();

// simple header-based auth (enabled only if ADMIN_KEY is set)
router.use((req, res, next) => {
  const requiredKey = process.env.ADMIN_KEY?.trim();
  if (!requiredKey) return next(); // open in dev if key not set
  const got = (req.header("X-Admin-Key") || "").trim();
  if (got && got === requiredKey) return next();
  return res.status(401).json({ ok: false, message: "Unauthorized" });
});

// list services
router.get("/services", async (_req, res) => {
  try {
    const list = await prisma.service.findMany({
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        name: true,
        description: true,
        durationMin: true,
        priceCents: true,
      },
    });
    res.json({ ok: true, data: list });
  } catch (e) {
    const err = e && typeof e === "object" && "message" in e ? (e as any).message : "Server error";
    res.status(500).json({ ok: false, message: String(err) });
  }
});

// create service
router.post("/services", async (req, res) => {
  try {
    const { name, description, durationMin, priceCents } = req.body ?? {};
    if (!name || typeof name !== "string") {
      return res.status(400).json({ ok: false, message: "Укажите name" });
    }
    const dur = Number(durationMin);
    const price = Number(priceCents);
    if (!Number.isFinite(dur) || dur <= 0) {
      return res.status(400).json({ ok: false, message: "Некорректная длительность" });
    }
    if (!Number.isFinite(price) || price < 0) {
      return res.status(400).json({ ok: false, message: "Некорректная цена" });
    }

    const created = await prisma.service.create({
      data: {
        name: name.trim(),
        description: description ? String(description) : null,
        durationMin: dur,
        priceCents: price,
      },
      select: { id: true, name: true, description: true, durationMin: true, priceCents: true },
    });
    res.json({ ok: true, data: created });
  } catch (e) {
    const err = e && typeof e === "object" && "message" in e ? (e as any).message : "Server error";
    res.status(500).json({ ok: false, message: String(err) });
  }
});

// update service
router.put("/services/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, durationMin, priceCents } = req.body ?? {};
    const data: any = {};
    if (name !== undefined) data.name = String(name).trim();
    if (description !== undefined) data.description = description ? String(description) : null;
    if (durationMin !== undefined) {
      const dur = Number(durationMin);
      if (!Number.isFinite(dur) || dur <= 0) {
        return res.status(400).json({ ok: false, message: "Некорректная длительность" });
      }
      data.durationMin = dur;
    }
    if (priceCents !== undefined) {
      const price = Number(priceCents);
      if (!Number.isFinite(price) || price < 0) {
        return res.status(400).json({ ok: false, message: "Некорректная цена" });
      }
      data.priceCents = price;
    }

    const updated = await prisma.service.update({
      where: { id },
      data,
      select: { id: true, name: true, description: true, durationMin: true, priceCents: true },
    });
    res.json({ ok: true, data: updated });
  } catch (e) {
    const err = e && typeof e === "object" && "message" in e ? (e as any).message : "Server error";
    res.status(500).json({ ok: false, message: String(err) });
  }
});

// delete service
router.delete("/services/:id", async (req, res) => {
  try {
    const { id } = req.params;
    await prisma.service.delete({ where: { id } });
    res.json({ ok: true });
  } catch (e) {
    const err = e && typeof e === "object" && "message" in e ? (e as any).message : "Server error";
    res.status(500).json({ ok: false, message: String(err) });
  }
});

export default router;
