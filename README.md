# Pino-HTTP build fix (3.0.3)

Ошибка сборки:
> Type 'typeof import(".../pino-http/index")' has no call signatures.

## Что поменять

1) Замените импорт `pino-http` в `src/index.ts` на default-импорт **и** вызов без аргументов:

```ts
// ПЛОХО:
// import * as pinoHttp from 'pino-http'
// import { pinoHttp } from 'pino-http'

// ПРАВИЛЬНО:
import pinoHttp from 'pino-http'
app.use(pinoHttp())
```

2) Замените ваш `tsconfig.json` на этот (NodeNext + esModuleInterop).

3) Пересоберите:
```bash
npm ci
npm run build
```

## Примечание по ESM
Так как используется `module: "NodeNext"`, в относительных импортах внутри `.ts` файлов указывайте **расширение `.js`**, например:
```ts
import { db } from './db.js'
```
(TypeScript перепишет его в runtime-корректный импорт в `dist`)
