
# Variant A — Fix Pack (Express + Prisma)

Дата: 2025-10-04T09:46:14.400910Z

## Что исправлено
1. **Зависимости/типы** — все типы и `typescript` перенесены в `dependencies`, чтобы компиляция проходила в Railway (где devDeps игнорируются).
2. **tsconfig** — NodeNext, strict + skipLibCheck, корректные `rootDir/outDir`.
3. **Prisma схема** — поля и связи приведены к используемым эндпоинтам:
   - `Client.tgUserId` помечен `@unique`.
   - Убраны несуществующие поля вроде `location`.
4. **Сервер** — типизированный Express с маршрутами:
   - `GET /api/services`
   - `POST /api/appointments` (upsert клиента по `tgUserId`)
   - `GET/POST/PUT/DELETE /admin/api/services`

## Быстрый старт локально
```bash
npm i
npx prisma generate
npm run build
npm start
```

## Railway
Твоё `start` уже запускает `prisma migrate deploy && prisma db push`.
```bash
railway run npm i
railway run npm run build
railway logs
```

## Интеграция в твой репозиторий
Скопируй из этого архива **четыре** файла/папки и замени свои:
- `package.json`
- `tsconfig.json`
- `prisma/schema.prisma`
- `src/index.ts` (или адаптируй пути, если у тебя `src/main.ts`/Nest)

Если у тебя остаётся Nest-проект в `services/api`, реши одну из стратегий:
- **A.** Использовать корневой Express (из этого пакета) — тогда убери старые скрипты/конфликты.
- **B.** Оставить Nest: поменяй `scripts.build` на `tsc -p services/api/tsconfig.json`, `start` на `node services/api/dist/main.js` и перенеси зависимости туда же.
```

