# web_app_appointments (v2.1.1)

Минимальный, проверенный на Node 22 каркас: Express + Prisma + Zod + Pino, Dockerfile для Railway.

## Запуск локально
```bash
npm install
npm run build
node dist/index.js
# http://localhost:8080/
```

## Переменные окружения
- `PORT` (по умолчанию 8080)
- `DATABASE_URL` — строка подключения Postgres для Prisma

## Деплой на Railway (с Dockerfile)
- Убедитесь, что в корне репозитория есть `Dockerfile` (из этого архива).
- Railway сам подхватит Dockerfile ("Using Detected Dockerfile").
- Пропишите `DATABASE_URL` в переменных проекта.
- После деплоя проверяйте:
  - `/` — публичная страница
  - `/admin` — мини-админка
  - `/health` — живость
  - `/api/ping-db` — проверка коннекта к БД
```

## Структура
- `src/index.ts` — сервер и маршруты
- `public/` — статика, в том числе админка
- `prisma/schema.prisma` — базовая схема (пока без моделей)
- `docker/entrypoint.sh` — запуск внутри контейнера
- `Dockerfile` — сборка и запуск
- `.dockerignore` — исключения
