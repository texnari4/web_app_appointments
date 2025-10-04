
# Appointments API (Express + Prisma + Zod + Pino) — Sprint 1

## Endpoints
- `GET /health`
- **Masters**
  - `GET /masters`
  - `POST /masters`
  - `GET /masters/:id`
  - `PUT /masters/:id`
  - `DELETE /masters/:id`
  - `POST /masters/:id/services` — link service to master `{ serviceId }`
- **Services**
  - `GET /services`
  - `POST /services`
  - `GET /services/:id`
  - `PUT /services/:id`
  - `DELETE /services/:id`
- **Appointments**
  - `GET /appointments?masterId=&from=&to=`
  - `POST /appointments`
  - `PUT /appointments/:id`
  - `DELETE /appointments/:id`

## Local Development
```bash
npm install
npx prisma generate
npx prisma db push
npm run build
npm start
```

## Docker
Environment var: `DATABASE_URL` (Postgres). Port: `8080`.
Railway auto-detects Dockerfile.

## Notes
- Node 22 compatible, CommonJS modules, `esModuleInterop: true`.
- Prisma CLI runs inside the container via `entrypoint.sh`, avoiding "prisma: not found".
