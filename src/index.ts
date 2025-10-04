import express from "express";
import cors from "cors";
import path from "path";
import pinoHttp from "pino-http";
import { PrismaClient } from "@prisma/client";

const app = express();
const prisma = new PrismaClient();

app.use(
  pinoHttp({
    autoLogging: true,
    redact: ["req.headers.authorization"],
  })
);

app.use(cors());
app.use(express.json());

const publicDir = path.join(__dirname, "..", "public");
app.use(express.static(publicDir));

app.get("/", (_req, res) => {
  res.sendFile(path.join(publicDir, "index.html"));
});

app.get("/admin", (_req, res) => {
  res.sendFile(path.join(publicDir, "admin", "index.html"));
});

app.get("/health", (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

app.get("/api/ping-db", async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ ok: true });
  } catch (e:any) {
    console.error(e);
    res.status(500).json({ ok: false, error: "db-failed" });
  }
});

app.use("/api", (_req, res) => {
  res.status(404).json({ error: "Not found" });
});

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
app.listen(PORT, () => {
  console.log(`Server started on :${PORT}`);
});
