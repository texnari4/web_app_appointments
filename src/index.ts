import express, { Request, Response, NextFunction } from "express";
import cors from "cors";
import pino from "pino";
import pinoHttp from "pino-http";
import { PrismaClient } from "@prisma/client";

const logger = pino({ level: process.env.NODE_ENV === "production" ? "info" : "debug" });

const app = express();
const prisma = new PrismaClient();

app.use(express.json());
app.use(cors());
app.use(pinoHttp({ logger }));

const PORT = parseInt(process.env.PORT || "8080", 10);

// Healthcheck
app.get("/health", (_req: Request, res: Response) => {
  res.status(200).send("ok");
});

// Minimal routes just to verify compile/runtime
app.get("/services", async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const items = await prisma.service.findMany({ orderBy: { name: "asc" } });
    res.json(items);
  } catch (e) {
    next(e);
  }
});

app.post("/services", async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { name, description, price, durationMin } = req.body ?? {};
    const created = await prisma.service.create({
      data: { name, description, price, durationMin }
    });
    res.status(201).json(created);
  } catch (e) {
    next(e);
  }
});

// Error handler
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  logger.error({ err }, "Unhandled error");
  res.status(500).json({ error: "Internal Server Error" });
});

app.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});