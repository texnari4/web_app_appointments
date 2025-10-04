# Beauty Mini App Appointments — MVP

Сервер на Express + Prisma для записи клиентов. Мини-админка для CRUD услуг.

## Быстрый старт локально

```bash
cp .env.example .env
# заполни DATABASE_URL
npm install
npx prisma generate
npm run build
npm run start
```

Открой `http://localhost:8080/admin` — форма добавления услуг и список.

## Railway

- Переменные окружения: `DATABASE_URL`, `PORT` (8080), `SLOT_STEP_MIN` (30) и др.
- Railpack выполняет `npm install` → `npm run build` → `npm run start`.
- В `start` мы запускаем `prisma:sync`, а `prisma` и `typescript` находятся в **dependencies**, чтобы CLI и компилятор были доступны в рантайме.

## Сид тестовых данных

```bash
npm run seed
```

Импортирует `data/test-data.json` (услуги, мастера).

## API (минимум)

- `GET /api/services`
- `POST /api/services` — `{ name, description?, priceCents?, durationMin, isActive? }`
- `PUT /api/services/:id`
- `DELETE /api/services/:id`
- `GET /api/appointments`
- `POST /api/appointments` — `{ clientId? | client?: {name?, phone?, tgUserId?}, serviceId, masterId?, startAt }`

## Соглашения по схеме

- `Client.tgUserId` — **уникальный**. Код использует `findUnique({ where: { tgUserId } })`.
- Поля дат: `startAt`, `endAt`. Продолжительность берётся из `Service.durationMin`.
