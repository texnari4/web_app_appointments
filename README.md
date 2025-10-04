# Web App Appointments — v2.3.4

Stack: Express + Prisma + Zod + Pino, Node 22, Docker (Alpine). CJS build for predictable deploys on Railway.

## Local dev
```bash
npm i
cp .env.example .env   # заполни DATABASE_URL
npm run prisma:sync
npm run dev
```

## Build
```bash
npm run build
```

## Prod (Docker)
- Используй предоставленный `Dockerfile` и `docker/entrypoint.sh`.
- Контейнер стартует на `$PORT` (по умолчанию 8080).

Routes:
- `GET /health`
- `GET /admin` — простая страница создания мастеров
- `GET /api/masters`
- `POST /api/masters` { name }
