import crypto from 'crypto';
import type { Request, Response, NextFunction } from 'express';
import { config } from '../config';
import { query } from '../db';

export function verifyInitData(initData: string): boolean {
  if (!initData) return false;
  const urlParams = new URLSearchParams(initData);
  const hash = urlParams.get('hash');
  if (!hash) return false;
  urlParams.delete('hash');
  const dataCheckString = Array.from(urlParams.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}=${v}`)
    .join('\n');
  const secretKey = crypto.createHmac('sha256', 'WebAppData').update(config.telegramBotToken).digest();
  const calcHash = crypto.createHmac('sha256', secretKey).update(dataCheckString).digest('hex');
  return calcHash === hash;
}

export async function telegramAuthMiddleware(req: Request, res: Response, next: NextFunction) {
  const initData = (req.headers['x-telegram-init-data'] as string) || (req.query.init_data as string) || '';
  if (!verifyInitData(initData)) {
    return res.status(401).json({ error: 'Invalid Telegram init data' });
  }
  const urlParams = new URLSearchParams(initData);
  const userStr = urlParams.get('user');
  let tgUserId: number | null = null;
  try {
    if (userStr) {
      const user = JSON.parse(userStr);
      tgUserId = user.id;
      (req as any).tgUser = user;
    }
  } catch {}

  let role: 'client' | 'master' | 'admin' = 'client';
  let masterId: string | null = null;
  let clientId: string | null = null;

  if (tgUserId) {
    const admin = await query<{ id: string }>('SELECT id FROM administrators WHERE telegram_user_id = $1', [tgUserId]);
    if (admin.rows.length) role = 'admin';
    const master = await query<{ id: string }>('SELECT id FROM masters WHERE telegram_user_id = $1', [tgUserId]);
    if (master.rows.length) { role = role === 'admin' ? 'admin' : 'master'; masterId = master.rows[0].id; }
    const client = await query<{ id: string }>('SELECT id FROM clients WHERE telegram_user_id = $1', [tgUserId]);
    if (client.rows.length) clientId = client.rows[0].id;
    else {
      const first_name = (req as any).tgUser?.first_name || null;
      const last_name = (req as any).tgUser?.last_name || null;
      const username = (req as any).tgUser?.username || null;
      const created = await query<{ id: string }>('INSERT INTO clients(telegram_user_id, first_name, last_name, username) VALUES ($1,$2,$3,$4) RETURNING id', [tgUserId, first_name, last_name, username]);
      clientId = created.rows[0].id;
    }
  }

  (req as any).auth = { role, tgUserId, masterId, clientId };
  next();
}
