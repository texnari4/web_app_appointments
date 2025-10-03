import type { Request, Response } from "express";

function getBaseUrl(): string | null {
  const fromEnv = process.env.PUBLIC_BASE_URL || process.env.RAILWAY_URL;
  if (!fromEnv) return null;
  if (fromEnv.startsWith("http://") || fromEnv.startsWith("https://")) return fromEnv.replace(/\/+$/, "");
  return `https://${fromEnv.replace(/\/+$/, "")}`;
}

async function callTelegram(method: string, params: URLSearchParams | undefined = undefined) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error("TELEGRAM_BOT_TOKEN is not set");
  const url =
    params && params.toString().length > 0
      ? `https://api.telegram.org/bot${token}/${method}?${params.toString()}`
      : `https://api.telegram.org/bot${token}/${method}`;
  const res = await fetch(url, { method: "POST" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || (data && data.ok === false)) {
    throw new Error(`Telegram API error for ${method}: ${res.status} ${res.statusText} ${JSON.stringify(data)}`);
  }
  return data;
}

export async function installWebhookIfNeeded(): Promise<void> {
  if (process.env.AUTO_SET_WEBHOOK !== "true") return;

  const base = getBaseUrl();
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token || !base) return;

  const webhookUrl = `${base}/tg/webhook`;
  const params = new URLSearchParams({ url: webhookUrl });

  try {
    await callTelegram("setWebhook", params);
    console.log(`[tg] setWebhook OK → ${webhookUrl}`);
  } catch (e) {
    console.error("[tg] setWebhook failed:", e);
  }
}

export async function handleTelegramWebhook(req: Request, res: Response) {
  try {
    const update = req.body;
    const msg = update?.message;
    const text: string | undefined = msg?.text;
    if (msg?.chat?.id && typeof text === "string") {
      if (text.startsWith("/start")) {
        const chatId = String(msg.chat.id);
        const params = new URLSearchParams({
          chat_id: chatId,
          text: "Привет! Мини‑приложение работает. Открой WebApp из бота, чтобы записаться 👇"
        });
        await callTelegram("sendMessage", params);
      }
    }
    res.status(200).json({ ok: true });
  } catch (e) {
    console.error("[tg] webhook error:", e);
    res.status(200).json({ ok: true });
  }
}
