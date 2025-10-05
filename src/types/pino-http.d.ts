// Local shim to avoid TS 'no call signatures' issue under NodeNext/ESM.
// Runtime remains unaffected. You can remove this if pino-http updates typings.
declare module 'pino-http' {
  const pinoHttp: any;
  export default pinoHttp;
}
