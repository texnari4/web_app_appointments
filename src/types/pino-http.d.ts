// Local shim to make pino-http callable under NodeNext in strict TS builds
declare module 'pino-http' {
  interface Options { [k: string]: any }
  type PinoHttp = (opts?: Options) => any
  const pinoHttp: PinoHttp
  export = pinoHttp
}
