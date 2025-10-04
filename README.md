# Web App Appointments (Express + Prisma + Zod + Pino)

## Run locally
```bash
npm install
npx prisma generate
npm run build
npm start
```

Health: `GET /health`

Admin UI (static): `GET /admin`

API:
- `GET /api/masters`, `POST /api/masters { name }`
- `GET /api/services`, `POST /api/services { title, priceCents, durationMin }`
- `GET /api/appointments`, `POST /api/appointments { masterId, serviceId, startsAt, endsAt, customerName, customerPhone }`

## Docker
Build and run:
```bash
docker build -f docker/Dockerfile -t web-app-appointments .
docker run --rm -p 8080:8080 -e DATABASE_URL="postgresql://..." web-app-appointments
```
```