# Quality Gates Patch (v2.3.7)

Этот пакет добавляет "страховочные барьеры", чтобы ошибки с переменными (`req` vs `_req`), отсутствующие экспорты и другие базовые вещи ловились **до** билда/деплоя.

## Что внутри
- `.eslintrc.cjs` — строгие правила для TypeScript/Node 22
- `.prettierrc` — форматирование
- `scripts/verify.sh` — единая команда проверки локально и в Dockerfile

## Как применить
1. Скопируй файлы в корень проекта:
   - `.eslintrc.cjs`
   - `.prettierrc`
   - `scripts/verify.sh` (дать права на исполнение: `chmod +x scripts/verify.sh`)

2. Обнови `package.json` (добавь/уточни скрипты):
```json
{
  "scripts": {
    "typecheck": "tsc -p tsconfig.json --noEmit",
    "lint": "eslint . --ext .ts",
    "format": "prettier --check .",
    "format:fix": "prettier --write .",
    "verify": "scripts/verify.sh",
    "build": "tsc -p tsconfig.json"
  },
  "devDependencies": {
    "@typescript-eslint/eslint-plugin": "^8.9.0",
    "@typescript-eslint/parser": "^8.9.0",
    "eslint": "^9.11.1",
    "prettier": "^3.3.3"
  }
}
```

3. (Опционально, но рекомендую) — В `Dockerfile` заставь пайплайн падать раньше:
   ```dockerfile
   # после npm install, до сборки:
   RUN npm run typecheck && npm run lint
   # затем:
   RUN npm run build
   ```

4. Запускай проверку локально перед коммитом:
   ```bash
   npm run verify
   ```

### Почему это решит наши «req/_req» проблемы?
- `@typescript-eslint/no-unused-vars` с `argsIgnorePattern: "^_"` ровно под это и заточен: 
  если параметр не используется — имя с `_` допустимо; если используется, он **должен** быть без подчёркивания, иначе ESLint упадёт.
- `no-undef` отловит обращения к несуществующим переменным.
- `tsc --noEmit` гарантирует, что типы и экспорты корректны до билда.

Если хочешь — добавлю git hook `pre-commit`, который будет гонять `npm run verify` автоматически.
