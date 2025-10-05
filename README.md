# Beauty Mini App Appointments — v2.5.0 (filesystem)

**Что внутри**
- Node.js 22 + TypeScript → Express API
- Файловая БД (JSON) в каталоге `DATA_DIR` (по умолчанию `/app/data`)
- Админка на `/admin` для CRUD мастеров
- Без Prisma/Redis/pino-http

## Запуск локально
```bash
npm install
npm run build
npm start
```
Открой `http://localhost:8080/admin`

## Эндпоинты
- `GET /health` → `{ ok: true, ts }`
- `GET /api/masters` → список
- `POST /api/masters` → создать (`{name, phone, specialty?, photoUrl?}`)
- `PATCH /api/masters/:id` → обновить
- `DELETE /api/masters/:id` → удалить

## Персистентность
- Укажи `DATA_DIR` через переменную окружения или примонтируй volume на `/app/data`.
- Railway: создай Volume и примонтируй в `/app/data`.

## Dockerfile
Мультистейдж: сборка → рантайм (node:22-bookworm-slim). 
Приложение запускается командой `node dist/index.js`.
