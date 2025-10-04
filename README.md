# Web App Appointments — v2.3.0

Каркас с CRUD Masters (Express + Prisma + Zod + Pino).

## Запуск локально

```bash
npm install
npx prisma generate
# c PostgreSQL в переменной DATABASE_URL
npx prisma migrate dev --name init
npm run build
npm start
```

## Docker

```bash
docker build -t web-app-appointments:2.3.0 .
docker run -p 8080:8080 -e PORT=8080 -e DATABASE_URL="postgresql://..." web-app-appointments:2.3.0
```

## Роуты

- `GET /health`
- `GET /` (стартовая), `GET /admin`
- `GET /api/masters`, `POST /api/masters`
- `GET /api/masters/:id`, `PUT /api/masters/:id`, `DELETE /api/masters/:id`

## Миграции
Миграции не запускаются автоматически на старте контейнера.
На Railway используй:
```
railway run npx prisma migrate deploy
```
Либо запустить локально `migrate dev` и закоммитить `prisma/migrations/`.
