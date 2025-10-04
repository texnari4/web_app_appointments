import { query } from '../db';

export async function enqueueNotification(kind: string, payload: any, channelId?: number, scheduledAt?: Date) {
  await query(
    `INSERT INTO notifications_outbox(kind, channel_id, payload, scheduled_at, status) VALUES($1,$2,$3,COALESCE($4,NOW()),'queued')`,
    [kind, channelId || null, payload, scheduledAt || null]
  );
}
