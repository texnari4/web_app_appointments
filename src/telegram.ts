import { Router, Request, Response } from 'express';

export const tgRouter = Router();

// Simple webhook endpoint (Telegram will POST updates here)
tgRouter.post('/webhook', async (req: Request, res: Response) => {
  // For sprint-1 we just acknowledge updates and log minimal info
  try {
    const update = req.body;
    console.log('[tg:update]', JSON.stringify(update));
  } catch (e) {
    console.error('[tg] webhook error', e);
  }
  res.sendStatus(200);
});

// Helper to set webhook on startup
export async function installWebhook(baseUrl: string, botToken?: string) {
  if (!botToken) return;
  if (!baseUrl) return;
  const url = `${baseUrl.replace(/\/$/, '')}/tg/webhook`;
  try {
    const resp = await fetch(`https://api.telegram.org/bot${botToken}/setWebhook`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url }),
    });
    const data = await resp.json();
    if (data.ok) {
      console.log('[tg] setWebhook OK →', url);
    } else {
      console.error('[tg] setWebhook failed', data);
    }
  } catch (e) {
    console.error('[tg] setWebhook exception', e);
  }
}
