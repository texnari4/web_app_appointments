import { Router, Request, Response } from 'express';

const token = process.env.TELEGRAM_BOT_TOKEN ?? '';

export const telegramRouter = Router();

telegramRouter.post('/', async (req: Request, res: Response) => {
  try {
    const update = req.body as any;

    const chatId: number | undefined =
      update?.message?.chat?.id ??
      update?.callback_query?.message?.chat?.id;

    if (chatId) {
      await sendMessage(chatId, '✅ Webhook is alive');
    }

    res.sendStatus(200);
  } catch (e) {
    console.error('[tg] webhook error', e);
    res.sendStatus(200);
  }
});

export async function installWebhook(url: string): Promise<void> {
  if (!token) throw new Error('TELEGRAM_BOT_TOKEN is empty');

  const r = await fetch(`https://api.telegram.org/bot${token}/setWebhook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ url })
  });

  if (!r.ok) {
    const body = await r.text();
    throw new Error(`setWebhook ${r.status}: ${body}`);
  }
}

async function sendMessage(chatId: number, text: string): Promise<void> {
  if (!token) return;

  await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, text })
  });
}