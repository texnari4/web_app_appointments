// Local shim to make TypeScript happy with `pino-http` under NodeNext/ESM.
// This does not affect runtime, only typings.
declare module 'pino-http' {
  const pinoHttp: any;
  export default pinoHttp;
}
