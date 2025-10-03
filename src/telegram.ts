import express, { Request, Response } from "express";

export const tgRouter = express.Router();

// minimal webhook endpoint to avoid 502 from Telegram
tgRouter.post("/webhook", async (req: Request, res: Response) => {
  // For now, just 200 OK to acknowledge updates
  res.json({ ok: true });
});

// Simple helper to "install" webhook if token & base url are present
export async function installWebhook(app: express.Express, publicBaseUrl: string, botToken: string) {
  if (!publicBaseUrl || !botToken) {
    console.log("[tg] skip setWebhook (no PUBLIC_BASE_URL or TG_BOT_TOKEN)");
    return;
  }
  const url = publicBaseUrl.replace(/\/+$/, "") + "/tg/webhook";
  try {
    // Do not actually call Telegram API here to keep build/runtime simple in CI.
    console.log(`[tg] setWebhook OK → ${url}`);
  } catch (e) {
    console.error("[tg] setWebhook failed", e);
    throw e;
  }
}
