# web-app-appointments (v2.3.5)

Express + Prisma + Zod + Pino • Node 22 • Dockerized • Railway ready

## Endpoints
- `GET /health`
- `GET /api/masters`
- `POST /api/masters` ({ name })
- `GET /admin` — простая панель управления

## Prisma
Таблица: `public.masters` (фиксирует опечатку "Macter").
Поля: id (cuid), name, created_at, updated_at.

## Run locally
```bash
npm i
export DATABASE_URL="postgresql://..."
npm run prisma:sync
npm run build
npm start
```

## Docker
```bash
docker build -t web-app-appointments:2.3.5 .
docker run -p 8080:8080 -e DATABASE_URL="postgresql://..." web-app-appointments:2.3.5
```