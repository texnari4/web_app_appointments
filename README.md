# pino-http typings hotfix (3.0.4)

This bundle fixes the TS build error:

  > Type 'typeof import("pino-http")' has no call signatures.

## What’s inside
- `tsconfig.json` — NodeNext + interop, includes `./src/types` in `typeRoots`.
- `src/types/pino-http.d.ts` — local type shim that declares a default export.

## Apply
1. Copy `tsconfig.json` to the project root (replace existing).
2. Copy the whole folder `src/types` into your project (so the file ends up at `src/types/pino-http.d.ts`).
3. Ensure your import stays as:

   ```ts
   import pinoHttp from 'pino-http';
   app.use(pinoHttp());
   ```

4. Rebuild:

   ```bash
   npm ci
   npm run build
   ```

## Why this helps
In NodeNext/ESM projects, the `pino-http` type definitions can be interpreted as a namespace instead of a callable function.
The shim forces TypeScript to treat the default export as `any` (callable), which matches actual runtime behavior.

*At runtime nothing changes — the shim is types-only.*
