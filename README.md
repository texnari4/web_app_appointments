# web-app-appointments (v2.1.2)
Minimal Express + Prisma + Zod + Pino baseline, Dockerized for Railway/Node 22.

## Dev
npm install
npx prisma generate
npm run build
npm start

## Docker
docker build -f docker/Dockerfile -t web-app-appointments .
docker run --rm -p 8080:8080 -e DATABASE_URL="postgresql://user:pass@host:5432/db" web-app-appointments

## Routes
GET /health
GET/POST /api/masters
GET/POST /api/services
GET/POST /api/appointments
Static admin at /admin
