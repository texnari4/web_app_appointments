# Hotfix: make sure `dist/` is generated

Apply these files to your repo root:

- `Dockerfile` — multi-stage build; fails early if `dist/` is missing.
- `tsconfig.json` — emits JS into `./dist` with NodeNext settings.
- `src/types/pino-http.d.ts` — local shim so `pino-http` is callable in TS.

## Checklist

1) Ensure `package.json` has:
   {
     "scripts": {
       "build": "tsc -p tsconfig.json",
       "start": "node dist/index.js"
     },
     "devDependencies": {
       "typescript": "^5.5.0",
       "@types/node": "^20.0.0"
     }
   }

2) In your TS source, when importing your own files under NodeNext,
   use explicit `.js` extensions, e.g. `import { db } from "./db.js"`.

3) Railway: keep the data volume mounted at `/app/data`.

Re-deploy after replacing files.
