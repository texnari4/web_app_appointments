import express, { Request, Response, NextFunction } from "express";
import cors from "cors";
import pinoHttp from "pino-http";
import path from "path";
import { prisma } from "./prisma";
import { masterCreateSchema } from "./validators";

const app = express();
const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;

app.use(express.json());
app.use(cors());
app.use(pinoHttp());

// Health
app.get("/health", (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// Static (admin)
app.use("/public", express.static(path.join(process.cwd(), "public")));
app.get("/admin", (_req, res) => {
  res.sendFile(path.join(process.cwd(), "public", "admin", "index.html"));
});

// API: Masters
app.get("/api/masters", async (_req, res, next) => {
  try {
    const rows = await prisma.master.findMany({ orderBy: { id: "desc" } });
    res.json(rows);
  } catch (e) { next(e); }
});

app.post("/api/masters", async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = masterCreateSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: "VALIDATION_ERROR", details: parsed.error.flatten() });
    }
    const master = await prisma.master.create({ data: parsed.data });
    res.status(201).json(master);
  } catch (e) { next(e); }
});

// 404 JSON
app.use((_req, res) => {
  res.status(404).json({ error: "NOT_FOUND" });
});

// Error handler
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  console.error(err);
  res.status(500).json({ error: "INTERNAL_ERROR" });
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server started on :${PORT}`);
});
