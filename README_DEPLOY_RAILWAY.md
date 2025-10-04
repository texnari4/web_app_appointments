# Beauty Booking — Railway Deploy

1. Создайте проект в Railway, подключите этот репозиторий.
2. Добавьте сервис **api** (Root directory: `apps/api`), команда build: `pnpm i && pnpm -C ../miniapp build && pnpm -C . build`, start: `node dist/index.js`.
3. (Опционально) добавьте сервис **worker** (Root directory: `apps/worker`), start: `node dist/worker.js`.
4. Подключите PostgreSQL и пропишите `DATABASE_URL` в Variables обоих сервисов.
5. Заполните `TELEGRAM_BOT_TOKEN`, `PUBLIC_BASE_URL`, и (если надо бэкапы) `GOOGLE_SERVICE_ACCOUNT_JSON`, `GOOGLE_SHEETS_BACKUP_SPREADSHEET_ID`.
6. Примените БД схему: `psql "$DATABASE_URL" -f packages/db/DB_SCHEMA.sql` (можно из CI или локально).
7. Откройте мини‑приложение через `https://<ваш-api>.railway.app` (в Telegram WebApp ссылку используйте как webapp URL).

Готово 👍
