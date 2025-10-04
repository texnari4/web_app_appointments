
# Beauty Mini App Appointments (API)

Express + Prisma (PostgreSQL) backend for salon appointments.

## Quick Start

```bash
npm install
npm run build
npm run seed   # optional
npm start
```

### Environment

Required envs (Railway already has many of them):

- `DATABASE_URL` (PostgreSQL)
- `PORT` (defaults 8080)
- `NODE_ENV`
- other project vars as needed

### Endpoints

- `GET /health`
- `GET /api/services`
- `POST /api/services`  `{ name, description?, price, durationMinutes }`
- `PUT /api/services/:id`
- `DELETE /api/services/:id`
- `POST /api/appointments` `{ clientName, clientPhone?, masterId, serviceId, startsAt }`
