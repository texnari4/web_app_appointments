import express from "express";
import path from "path";
import { fileURLToPath } from "url";
import { listMasters, createMaster, updateMaster, deleteMaster } from "./db";

// Since we compile to CommonJS, __dirname exists, but keep compatibility with ESM tools:
const __filename = (typeof __dirname !== 'undefined') ? __filename : fileURLToPath(import.meta.url);
const __basedir = (typeof __dirname !== 'undefined') ? __dirname : path.dirname(__filename);

const app = express();
const port = process.env.PORT || 8080;

// --- Minimal request logger (to avoid pino-http typing issues) ---
app.use((req, res, next) => {
  const started = Date.now();
  res.on("finish", () => {
    const ms = Date.now() - started;
    console.log(`[req] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${ms}ms)`);
  });
  next();
});

app.use(express.json());

// --- Static admin ---
const publicDir = path.join(__basedir, "..", "public");
app.use("/admin", express.static(path.join(publicDir, "admin")));

// --- Health ---
app.get("/health", (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

// --- API: masters ---
app.get("/api/masters", async (_req, res) => {
  try {
    const masters = await listMasters();
    res.json({ ok: true, data: masters });
  } catch (e) {
    res.status(500).json({ ok: false, error: "READ_FAILED" });
  }
});

app.post("/api/masters", async (req, res) => {
  try {
    const master = await createMaster(req.body);
    res.status(201).json({ ok: true, data: master });
  } catch (e: any) {
    if (e?.name === "ZodError") {
      res.status(400).json({ ok: false, error: "VALIDATION_FAILED", details: e.issues });
    } else {
      res.status(500).json({ ok: false, error: "CREATE_FAILED" });
    }
  }
});

app.patch("/api/masters/:id", async (req, res) => {
  try {
    const master = await updateMaster(req.params.id, req.body);
    res.json({ ok: true, data: master });
  } catch (e: any) {
    if (e?.message === "NOT_FOUND") {
      res.status(404).json({ ok: false, error: "NOT_FOUND" });
    } else if (e?.name === "ZodError") {
      res.status(400).json({ ok: false, error: "VALIDATION_FAILED", details: e.issues });
    } else {
      res.status(500).json({ ok: false, error: "UPDATE_FAILED" });
    }
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

// --- Root -> JSON 404 for Telegram mini app default route ---
app.get("/", (_req, res) => {
  res.status(404).json({ error: "NOT_FOUND" });
});

// --- Start ---
app.listen(port, () => {
  console.log(`Server started on :${port}`);
});
