# v2.3.8 — Fix: создание мастера из админки

## Что изменилось
- Бэкенд: исправлены маршруты `/api/masters` (GET/POST), добавлена строгая валидация через Zod.
- UI админки: форма «Создать» шлёт `POST /api/masters` и после успеха обновляет список, показывая тост.
- Pino-http подключён корректно (без ошибок типов), 404 и error handler не используют `req`.
- Docker: образ `node:22-bookworm-slim`, движки Prisma — Node-API.

## Локально
```bash
npm i
npx prisma generate
# Укажи DATABASE_URL в .env или переменных окружения
npm run dev
```

## Прод
Собирает Railway по Dockerfile. Нужна только переменная `DATABASE_URL`.
