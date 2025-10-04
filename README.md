# web_app_appointments (Dockerized, minimal stable baseline)

Node 22 + Express + Prisma + Zod + Pino. Docker-first, Alpine-friendly.

## Environment

Set `DATABASE_URL` to your PostgreSQL connection:
```
postgresql://user:pass@host:5432/dbname?schema=public
```

## Local (without Docker)
```bash
npm install
npm run build
DATABASE_URL="postgresql://..." npm start
```

## Docker
```bash
docker build -t web-app-appointments:latest .
docker run --rm -p 8080:8080   -e DATABASE_URL="postgresql://user:pass@host:5432/dbname?schema=public"   web-app-appointments:latest
```

### Healthcheck
GET http://localhost:8080/health → `{ ok: true, ts: ... }`