# Fix pack (Express + Prisma + Telegram)

## What changed
- Added `src/telegram.ts` with `tgRouter` and `installWebhook` exports.
- Fixed Prisma types usage in `src/index.ts`:
  - no writes to non-existent fields (`phone`, `priceBYN`, etc).
  - strict connects for required relations `service`, `staff`, `location`.
  - `findFirst` for client by `tgUserId`, create if not exists.
- Added CORS usage.

## Important
Install missing deps locally (Railway will also need them in package.json):
```
npm i cors
npm i -D @types/cors
```

## Env
- `PUBLIC_BASE_URL` must be your public host, e.g. `https://your-app.up.railway.app`
- `TG_BOT_TOKEN` optional; webhook log line is mocked to avoid network calls during boot.
