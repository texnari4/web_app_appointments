# Hotfix: pino-http typing + tsconfig

1. Replace your project's `tsconfig.json` with the one in this archive.
2. Add the file `src/types/pino-http.d.ts` (create folders if needed).
3. Keep your import as:
   ```ts
   import pinoHttp from 'pino-http';
   app.use(pinoHttp());
   ```
4. Rebuild:
   ```bash
   npm ci
   npm run build
   ```

If you prefer to remove pino-http entirely, use a simple logger middleware instead and uninstall the package.
