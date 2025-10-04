import 'dotenv/config';

export const config = {
  port: Number(process.env.PORT || 3000),
  databaseUrl: process.env.DATABASE_URL!,
  telegramBotToken: process.env.TELEGRAM_BOT_TOKEN!,
  publicBaseUrl: process.env.PUBLIC_BASE_URL || '',
  slotStepMin: Number(process.env.SLOT_STEP_MIN || 30),
  logLevel: process.env.LOG_LEVEL || 'info',
  sheets: {
    json: process.env.GOOGLE_SERVICE_ACCOUNT_JSON ? JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON) : null,
    spreadsheetId: process.env.GOOGLE_SHEETS_BACKUP_SPREADSHEET_ID || ''
  }
};
