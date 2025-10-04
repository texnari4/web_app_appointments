# Web App Appointments — v2.3.1 (Hotfix)

Hotfix: исправлен `POST /api/masters` (парсинг JSON, валидация Zod, корректный ответ/обновление списка на админке).

## Скрипты
- `npm run build` — компиляция TypeScript
- `npm start` — запуск скомпилированного кода
- `npm run prisma:generate` — генерация Prisma Client

## Переменные
- `PORT` (необяз.) — по умолчанию `8080`
- `DATABASE_URL` — строка подключения PostgreSQL
