# Hotfix: dist missing & pino-http typings

Apply these files to your repo root:
- Dockerfile (multi-stage, ensures `npm run build` produces ./dist)
- tsconfig.json (NodeNext + outDir ./dist)
- src/types/pino-http.d.ts (workaround typings)

Make sure your package.json contains scripts:
{
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "start": "node dist/index.js"
  },
  "devDependencies": {
    "@types/node": "^20"
  }
}

Then redeploy on Railway.
