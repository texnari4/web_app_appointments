import http from 'http';
import { readFile } from 'fs/promises';
import path from 'path';
import url from 'url';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { fileURLToPath } from 'url';
import { masterCreateSchema, MasterCreateInput } from './validators.js';
import { listMasters, addMaster, removeMaster } from './storage.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const httpLogger = pinoHttp({ logger });

const PUBLIC_DIR = path.join(__dirname, '..', 'public');
const PORT = Number(process.env.PORT) || 8080;

function sendJSON(res: http.ServerResponse, code: number, data: any) {
  const body = Buffer.from(JSON.stringify(data));
  res.statusCode = code;
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('content-length', String(body.length));
  res.end(body);
}

function sendText(res: http.ServerResponse, code: number, text: string) {
  const body = Buffer.from(text, 'utf-8');
  res.statusCode = code;
  res.setHeader('content-type', 'text/plain; charset=utf-8');
  res.setHeader('content-length', String(body.length));
  res.end(body);
}

async function serveStatic(req: http.IncomingMessage, res: http.ServerResponse): Promise<boolean> {
  const reqUrl = (req.url || '/');
  if (!reqUrl.startsWith('/public/') && reqUrl !== '/' && reqUrl !== '/admin/' && !reqUrl.startsWith('/admin/')) return false;

  let filePath: string;
  if (reqUrl === '/' ) filePath = path.join(PUBLIC_DIR, 'index.html');
  else if (reqUrl === '/admin/' || reqUrl === '/admin') filePath = path.join(PUBLIC_DIR, 'admin', 'index.html');
  else filePath = path.join(PUBLIC_DIR, reqUrl.replace(/^\/+/, ''));

  try {
    const data = await readFile(filePath);
    const ext = path.extname(filePath).toLowerCase();
    const ctype = ext === '.html' ? 'text/html; charset=utf-8'
      : ext === '.css' ? 'text/css; charset=utf-8'
      : ext === '.js' ? 'text/javascript; charset=utf-8'
      : 'application/octet-stream';
    res.statusCode = 200;
    res.setHeader('content-type', ctype);
    res.end(data);
    return true;
  } catch {
    return false;
  }
}

async function parseJsonBody(req: http.IncomingMessage): Promise<any> {
  return await new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on('data', (d) => chunks.push(d));
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf-8');
        if (!raw) return resolve({});
        resolve(JSON.parse(raw));
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  httpLogger(req, res);

  const method = req.method || 'GET';
  const parsed = url.parse(req.url || '/', true);
  const pathname = parsed.pathname || '/';

  try {
    // Health
    if (method === 'GET' && pathname === '/health') {
      return sendJSON(res, 200, { ok: true, ts: new Date().toISOString() });
    }

    // API (admin)
    if (pathname.startsWith('/admin/api/masters')) {
      if (method === 'GET') {
        const items = await listMasters();
        return sendJSON(res, 200, { items });
      }
      if (method === 'POST') {
        const body = await parseJsonBody(req);
        const parsedBody = masterCreateSchema.parse(body as MasterCreateInput);
        const created = await addMaster(parsedBody);
        return sendJSON(res, 201, created);
      }
      if (method === 'DELETE') {
        const id = String(parsed.query?.id || '');
        if (!id) return sendJSON(res, 400, { error: 'id is required' });
        const ok = await removeMaster(id);
        return sendJSON(res, ok ? 200 : 404, ok ? { ok: true } : { error: 'not found' });
      }
      return sendJSON(res, 405, { error: 'method not allowed' });
    }

    // Public + admin static
    const served = await serveStatic(req, res);
    if (served) return;

    // Fallback
    return sendJSON(res, 404, { error: 'NOT_FOUND' });
  } catch (e: any) {
    logger.error({ err: e }, 'request error');
    return sendJSON(res, 500, { error: 'INTERNAL_ERROR' });
  }
});

server.listen(PORT, () => {
  logger.info(`Server started on :${PORT}`);
});
