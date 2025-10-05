import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { listMasters, createMaster, updateMaster, deleteMaster } from "./db.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = process.env.PORT || 8080;

app.use((req, res, next) => {
  const started = Date.now();
  res.on("finish", () => {
    const ms = Date.now() - started;
    console.log(`[req] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${ms}ms)`);
  });
  next();
});

app.use(express.json());

const publicDir = path.join(__dirname, "..", "public");
app.use("/admin", express.static(path.join(publicDir, "admin")));

app.get("/health", (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

app.get("/api/masters", async (_req, res) => {
  try {
    const masters = await listMasters();
    res.json({ ok: true, data: masters });
  } catch {
    res.status(500).json({ ok: false, error: "READ_FAILED" });
  }
});

app.post("/api/masters", async (req, res) => {
  try {
    const master = await createMaster(req.body);
    res.status(201).json({ ok: true, data: master });
  } catch (e) {
    res.status(400).json({ ok: false, error: e.message || "CREATE_FAILED" });
  }
});

app.patch("/api/masters/:id", async (req, res) => {
  try {
    const master = await updateMaster(req.params.id, req.body);
    res.json({ ok: true, data: master });
  } catch (e) {
    res.status(400).json({ ok: false, error: e.message || "UPDATE_FAILED" });
  }
});

app.delete("/api/masters/:id", async (req, res) => {
  try {
    await deleteMaster(req.params.id);
    res.json({ ok: true });
  } catch {
    res.status(500).json({ ok: false, error: "DELETE_FAILED" });
  }
});

app.listen(port, () => console.log(`Server started on :${port}`));
