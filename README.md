# beauty_mini_app_appointments (backend)

Готовый минимальный backend для Railway:
- TypeScript (NodeNext)
- Express + pino-http
- Prisma (PostgreSQL)
- Zod валидаторы (готово к расширению)

## Скрипты

- `npm run build` — компиляция TypeScript в `dist/`
- `npm run start` — применяет миграции/генерацию клиента и запускает сервер
- `npm run prisma:sync` — `prisma migrate deploy && prisma db push && prisma generate`
- `node scripts/seed.mjs` — базовое наполнение справочников

## Переменные окружения

- `DATABASE_URL` — строка подключения к PostgreSQL
- `PORT` — порт (по умолчанию 8080)
- Другие переменные можно добавлять по мере необходимости.

## Заметки по Railway

Railway по умолчанию устанавливает зависимости в режиме production (omit dev).
Поэтому все пакеты, нужные для сборки и типов, перенесены в `dependencies`.