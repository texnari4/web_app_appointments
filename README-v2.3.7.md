# v2.3.7 — Prisma runtime fix (Railway)

## Что поменялось
- Базовый образ: `node:22-bookworm-slim` вместо Alpine. Это убирает проблемы с OpenSSL/musl.
- Явно ставим `openssl` и `ca-certificates`.
- Форсим использование Node-API движка Prisma:
  - `PRISMA_CLIENT_ENGINE_TYPE=library`
  - `PRISMA_CLI_QUERY_ENGINE_TYPE=library`
- В entrypoint:
  - всегда выполняется `prisma migrate deploy` (безопасно для продакшена);
  - `prisma db push` выполняется **только** если выставить `PRISMA_DB_PUSH=1` (и при необходимости `PRISMA_DB_PUSH_ACCEPT_DATA_LOSS=1`).

## Деплой
1. Замените свой `Dockerfile` и `docker/entrypoint.sh` на файлы из этого архива.
2. Закоммитьте и задеплойте.
3. Если потребуется форс-выкатить схему без миграций (осторожно!):
   - установите в Railway переменные окружения:
     - `PRISMA_DB_PUSH=1`
     - (опционально) `PRISMA_DB_PUSH_ACCEPT_DATA_LOSS=1`
   - перезапустите сервис, после чего **верните** эти переменные обратно пустыми.

## Примечание
Обновление до `prisma@^6` ещё сильнее снижает вероятность конфликтов с OpenSSL. Это можно сделать в одном из следующих релизов.
