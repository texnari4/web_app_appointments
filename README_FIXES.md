# Railway Build Fix — Variant A

Переносим TypeScript и `@types/*` в production-зависимости, настраиваем tsconfig,
и выравниваем Prisma-схему (уникальный `tgUserId`, базовые модели).

## Шаги

1) Обновите `services/api/package.json` и (при необходимости) `services/worker/package.json` —
   перенесите `typescript`, `ts-node`, `@types/*` в `dependencies`.
   Используйте файлы из `templates/` как ориентир.

2) Положите `templates/services/api/tsconfig.json` (и для worker) вместо ваших,
   либо внесите аналогичные опции: `noImplicitAny: true`, `skipLibCheck: true`, `outDir: dist`, `rootDir: src`.

3) Если код использует `tgUserId` и простые Appointment/Service — примените `templates/prisma/schema.prisma`
   (или перенесите только изменения — уникальный индекс и базовые поля).

4) Примените Prisma:
   ```
   npx prisma format
   npx prisma migrate dev -n "align_schema_with_code"
   ```

5) Деплойте на Railway.

## Почему это важно

Railway устанавливает только prod-зависимости, а у вас компиляция TS в CI.
Если `typescript` и `@types/*` сидят в devDeps, компилятор не найдёт типы.
