# web-app-appointments (Dockerized skeleton)

Минимальный каркас (Express + Prisma + Zod + Pino) для Node 22, с Dockerfile и корректным стартом миграций внутри контейнера.

## Локальный запуск

```bash
npm install
npm run build
# нужен DATABASE_URL
DATABASE_URL="postgresql://user:pass@host:5432/dbname?schema=public" npm start
```

## Docker

```bash
docker build -t web-app-appointments:latest .
docker run --rm -p 8080:8080       -e DATABASE_URL="postgresql://user:pass@host:5432/dbname?schema=public"       web-app-appointments:latest
```

Эндпоинты:
- `GET /health` — быстрая проверка.
- `POST /validate` — пример валидации через Zod: `{ "ping": "pong" }`

## Prisma

В контейнере при старте выполняется:
- `prisma generate`,
- `prisma migrate deploy` (если нет миграций — fallback на `prisma db push`).

Локально:
```bash
npx prisma generate
npx prisma migrate dev
npm run seed
```

## Дальше

Дальше добавляем модели (мастера/услуги/записи) в `prisma/schema.prisma`, генерируем клиент, наращиваем `src/`.
