# web-app-appointments (Dockerized)

## Env
- `DATABASE_URL` (PostgreSQL)

## Local
```bash
npm install
npx prisma generate
npx prisma db push
npm run build
npm start
```

## Docker
```bash
docker build -t appointments .
docker run --rm -p 8080:8080 -e DATABASE_URL="postgresql://user:pass@host:5432/db?schema=public" appointments
```

## Railway
- Set `Dockerfile` build.
- Set `DATABASE_URL`.
- Port 8080.
- Done.
```

