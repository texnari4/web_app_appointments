# web-app-appointments (v2.2.0)

Minimal Express + Prisma + Zod + Pino template for Node 22 with Dockerfile (Railway-ready).

## Routes
- `GET /` — static index
- `GET /admin` — simple admin page
- `GET /health` — liveness
- `GET /api/masters` — placeholder (returns empty list)
- alias: `GET /public/api/masters`

## Build & Run (Docker)
```bash
docker build -t web-app-appointments:2.2.0 .
docker run -p 8080:8080 -e PORT=8080 -e DATABASE_URL="postgresql://..." web-app-appointments:2.2.0
```

## Railway
Railway will auto-detect the Dockerfile.
Ensure you set `DATABASE_URL` in the environment.
