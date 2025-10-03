# Web App Appointments (Railway-ready)

Минимальная версия: Express + Prisma + статика, автоматическая установка Telegram webhook.

## Env
- `TELEGRAM_BOT_TOKEN` — токен бота
- `DATABASE_URL` — строка подключения к Postgres
- `PUBLIC_BASE_URL` — публичный URL приложения (https://your-app.up.railway.app)
- `AUTO_SET_WEBHOOK` — "true" для авто-установки webhook при старте

## Локально
```bash
npm install
npm run build
npm start
```

## Railway
- Root Directory: (корень репозитория)
- Build: `npm run build`
- Start: `npm run start`
- Vars: см. .env.example
