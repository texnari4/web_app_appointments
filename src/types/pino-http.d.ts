// Minimal local typings to avoid “no call signatures” on pino-http under NodeNext
declare module 'pino-http' {
  const pinoHttp: any;
  export default pinoHttp;
  export = pinoHttp;
}
