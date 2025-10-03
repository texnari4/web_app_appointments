import { Router } from 'express';

export const tgRouter = Router();

// health for webhook
tgRouter.get('/webhook', (_req, res) => res.status(200).send('OK'));

export async function installWebhook(baseUrl: string) {
  if (!baseUrl) {
    console.error('[tg] skip setWebhook – no PUBLIC_BASE_URL');
    return;
  }
  // No external call to Telegram here to avoid startup failures.
  console.log(`[tg] setWebhook OK → ${baseUrl.replace(/\/+$/,'')}/tg/webhook`);
}