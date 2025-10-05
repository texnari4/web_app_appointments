declare module "pino-http" {
  import type { IncomingMessage, ServerResponse } from "node:http";
  import type { LoggerOptions } from "pino";
  export interface PinoHttpOptions extends LoggerOptions {}
  function pinoHttp(opts?: PinoHttpOptions):
    (req: IncomingMessage, res: ServerResponse, next: (err?: any) => void) => void;
  export = pinoHttp;
}
