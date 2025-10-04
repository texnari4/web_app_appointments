import 'dotenv/config';
import { Client } from 'pg';
import TelegramBot from 'node-telegram-bot-api';
import cron from 'node-cron';

const botToken = process.env.TELEGRAM_BOT_TOKEN!;
const bot = new TelegramBot(botToken, { polling: false });
const client = new Client({ connectionString: process.env.DATABASE_URL });
await client.connect();

async function processOutbox() {
  const res = await client.query(`
    SELECT id, kind, channel_id, payload, scheduled_at
    FROM notifications_outbox
    WHERE status='queued' AND scheduled_at <= NOW()
    ORDER BY scheduled_at ASC
    LIMIT 50
  `);
  for (const row of res.rows) {
    try {
      const payload = row.payload;
      if (row.kind === 'tg_message') {
        if (payload.type === 'appointment_created') {
          const app = await client.query(`
            SELECT a.id, a.start_at, s.name AS service, m.name AS master, c.telegram_user_id
            FROM appointments a
            JOIN services s ON s.id=a.service_id
            JOIN masters m ON m.id=a.master_id
            JOIN clients c ON c.id=a.client_id
            WHERE a.id=$1
          `, [payload.appointment_id]);
          if (app.rows.length) {
            const a = app.rows[0];
            const text = `📅 Новая запись\nУслуга: ${a.service}\nМастер: ${a.master}\nВремя: ${new Date(a.start_at).toLocaleString()}`;
            if (a.telegram_user_id) await bot.sendMessage(a.telegram_user_id, text, { parse_mode: 'HTML' });
          }
        }
      }
      await client.query(`UPDATE notifications_outbox SET status='sent', sent_at=NOW(), error=NULL WHERE id=$1`, [row.id]);
    } catch (e:any) {
      await client.query(`UPDATE notifications_outbox SET status='failed', error=$2 WHERE id=$1`, [row.id, String(e)]);
    }
  }
}

cron.schedule('* * * * *', processOutbox);

cron.schedule('*/15 * * * *', async () => {
  const res = await client.query(`
    WITH targets AS (
      SELECT a.id, c.telegram_user_id, s.name as service, m.name as master, a.start_at
      FROM appointments a
      JOIN clients c ON c.id=a.client_id
      JOIN services s ON s.id=a.service_id
      JOIN masters m ON m.id=a.master_id
      WHERE a.status IN ('confirmed','pending')
        AND (ABS(EXTRACT(EPOCH FROM (a.start_at - NOW()))/3600) BETWEEN 1.9 AND 2.1 OR ABS(EXTRACT(EPOCH FROM (a.start_at - NOW()))/3600) BETWEEN 23.5 AND 24.5)
    )
    SELECT * FROM targets
  `);
  for (const t of res.rows) {
    if (!t.telegram_user_id) continue;
    const text = `🔔 Напоминание о записи: <b>${new Date(t.start_at).toLocaleString()}</b>\nУслуга: ${t.service}\nМастер: ${t.master}`;
    await bot.sendMessage(t.telegram_user_id, text, { parse_mode: 'HTML' });
  }
});

console.log('Worker started');
