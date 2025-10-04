import { google } from 'googleapis';
import { config } from '../config';
import { query } from '../db';

export async function backupAppointmentsToSheets() {
  if (!config.sheets.json || !config.sheets.spreadsheetId) return;
  const auth = new google.auth.GoogleAuth({ credentials: config.sheets.json, scopes: ['https://www.googleapis.com/auth/spreadsheets'] });
  const sheets = google.sheets({ version: 'v4', auth });
  const { rows } = await query(`
    SELECT a.id, a.start_at, a.end_at, a.status, s.name as service, m.name as master, c.first_name, c.last_name, a.price_minor
    FROM appointments a
    JOIN services s ON s.id=a.service_id
    JOIN masters m ON m.id=a.master_id
    JOIN clients c ON c.id=a.client_id
    ORDER BY a.start_at DESC LIMIT 1000
  `);
  const header = ['id','start_at','end_at','status','service','master','client_first_name','client_last_name','price_minor'];
  const values = [header, *rows.map((r:any)=>[r.id, r.start_at, r.end_at, r.status, r.service, r.master, r.first_name, r.last_name, r.price_minor])];
  await sheets.spreadsheets.values.update({
    spreadsheetId: config.sheets.spreadsheetId,
    range: 'appointments!A1',
    valueInputOption: 'RAW',
    requestBody: { values }
  });
}
