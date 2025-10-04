# Beauty Mini App Appointments — Variant A (Railway Ready)

## Install
```bash
npm install
```

## Local dev (needs DATABASE_URL set)
```bash
npm run prisma:sync
npm run dev
```

## Seed (optional)
```bash
npm run seed
```

## Build & Start
```bash
npm run build
npm start
```

### Notes
- Prisma CLI is in production deps so Railway can run `prisma` during start.
- TypeScript `rootDir` is `"."` and `include` captures `scripts/**/*.ts`.
- Zod is added to dependencies and `src/validators.ts` imports it.
