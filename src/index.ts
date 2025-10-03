// src/index.ts
import express, { Request, Response, NextFunction } from 'express';
import path from 'node:path';
import { prisma } from './prisma';
import { installWebhook, tgRouter } from './telegram';

const app = express();

// ---- Middlewares ----
app.use(express.json());
// Нужен для <form method="post"> из админки
app.use(express.urlencoded({ extended: true }));

// Статика (микро-страница мини-приложения)
app.use(express.static(path.join(process.cwd(), 'public')));

// ---- Health ----
app.get('/healthz', (_req, res) => res.status(200).send('ok'));

// ===============================
// Admin helpers (очень простой доступ по токену)
// ===============================
function isAdmin(req: Request): boolean {
  const token = (req.query.token as string) || (req.headers['x-admin-token'] as string | undefined);
  return !!token && token === process.env.ADMIN_TOKEN;
}

function requireAdmin(req: Request, res: Response, next: NextFunction) {
  if (!isAdmin(req)) return res.status(401).send('Unauthorized');
  next();
}

// ===============================
// API для мини-приложения
// ===============================

// Услуги (читаем)
app.get('/api/services', async (_req: Request, res: Response) => {
  try {
    const services = await prisma.service.findMany({
      orderBy: { name: 'asc' },
      select: { id: true, name: true, priceBYN: true, durationMin: true, description: true },
    });
    res.json({ ok: true, services });
  } catch (e) {
    console.error('[api] /api/services error', e);
    res.status(500).json({ ok: false, error: 'internal_error' });
  }
});

// Запись на приём (создаём)
app.post('/api/appointments', async (req: Request, res: Response) => {
  try {
    const { serviceId, staffId, locationId, clientId, client } = req.body ?? {};

    // Prisma требует связанные сущности по relation-полям
    // Заполняем их через connect либо create
    const data: any = {
      startAt: new Date(req.body?.startAt),
      endAt: new Date(req.body?.endAt),
      status: 'CREATED' as const,
      service: { connect: { id: serviceId } },
      staff: { connect: { id: staffId } },
      location: { connect: { id: locationId } },
      client:
        clientId
          ? { connect: { id: clientId } }
          : client
          ? {
              create: {
                tgUserId: client.tgUserId ?? null,
                phoneEnc: client.phoneEnc ?? null,
                emailEnc: client.emailEnc ?? null,
                firstName: client.firstName ?? null,
                lastName: client.lastName ?? null,
              },
            }
          : undefined,
    };

    const created = await prisma.appointment.create({ data });
    res.json({ ok: true, appointment: created });
  } catch (e) {
    console.error('[api] /api/appointments error', e);
    res.status(400).json({ ok: false, error: 'bad_request' });
  }
});

// ===============================
// Telegram webhook
// ===============================
app.use('/tg', tgRouter);

// ===============================
// Admin panel (Services CRUD)
// ===============================

app.get('/admin', requireAdmin, (_req, res) => res.redirect('/admin/services'));

app.get('/admin/services', requireAdmin, async (req: Request, res: Response) => {
  const qToken = (req.query.token as string) ?? '';
  const services = await prisma.service.findMany({ orderBy: { name: 'asc' } });

  const rows = services
    .map(
      (s) => `
      <tr>
        <td>#${s.id}</td>
        <td>
          <form method="post" action="/admin/services/${s.id}?token=${encodeURIComponent(qToken)}" style="display:flex;gap:6px;flex-wrap:wrap">
            <input type="text" name="name" value="${escapeHtml(s.name)}" required />
            <input type="number" step="1" min="0" name="durationMin" value="${s.durationMin ?? 0}" placeholder="Минуты" required />
            <input type="number" step="0.01" min="0" name="priceBYN" value="${s.priceBYN ?? 0}" placeholder="Цена BYN" required />
            <input type="text" name="description" value="${escapeHtml(s.description ?? '')}" placeholder="Описание" />
            <button type="submit">Сохранить</button>
          </form>
        </td>
        <td>
          <form method="post" action="/admin/services/${s.id}/delete?token=${encodeURIComponent(qToken)}" onsubmit="return confirm('Удалить услугу «${escapeAttr(
            s.name,
          )}»?')">
            <button type="submit" style="background:#c0392b;color:#fff">Удалить</button>
          </form>
        </td>
      </tr>`,
    )
    .join('');

  res.setHeader('Content-Type', 'text/html; charset=utf-8').send(`<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Админка — Услуги</title>
<style>
  body{font:14px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; padding:20px; max-width:980px; margin:0 auto;}
  h1{margin:0 0 16px;}
  table{width:100%; border-collapse: collapse;}
  td, th{border:1px solid #ddd; padding:8px; vertical-align:top;}
  form input{padding:6px 8px}
  form button{padding:6px 10px; cursor:pointer}
  .card{border:1px solid #eee; padding:12px; margin:16px 0; border-radius:8px; background:#fafafa}
  .grid{display:grid; grid-template-columns: 1fr; gap:8px}
  @media (min-width:720px){ .grid{grid-template-columns: repeat(4, 1fr);} }
</style>
</head>
<body>
  <h1>Админка — Услуги</h1>

  <div class="card">
    <h3>Добавить услугу</h3>
    <form method="post" action="/admin/services?token=${encodeURIComponent(qToken)}" class="grid">
      <input type="text" name="name" placeholder="Название" required />
      <input type="number" step="1" min="0" name="durationMin" placeholder="Длительность, мин" required />
      <input type="number" step="0.01" min="0" name="priceBYN" placeholder="Цена, BYN" required />
      <input type="text" name="description" placeholder="Описание (необязательно)" />
      <div>
        <button type="submit">Создать</button>
      </div>
    </form>
  </div>

  <table>
    <thead><tr><th>ID</th><th>Услуга</th><th>Действия</th></tr></thead>
    <tbody>${rows || '<tr><td colspan="3">Пока пусто</td></tr>'}</tbody>
  </table>
</body>
</html>`);
});

// Создать
app.post('/admin/services', requireAdmin, async (req: Request, res: Response) => {
  const { name, durationMin, priceBYN, description } = req.body ?? {};
  await prisma.service.create({
    data: {
      name: String(name),
      durationMin: Number.parseInt(durationMin),
      priceBYN: Number.parseFloat(priceBYN),
      description: description ? String(description) : null,
    },
  });
  res.redirect(`/admin/services?token=${encodeURIComponent(String(req.query.token ?? ''))}`);
});

// Обновить
app.post('/admin/services/:id', requireAdmin, async (req: Request, res: Response) => {
  const id = Number.parseInt(req.params.id);
  const { name, durationMin, priceBYN, description } = req.body ?? {};
  await prisma.service.update({
    where: { id },
    data: {
      name: String(name),
      durationMin: Number.parseInt(durationMin),
      priceBYN: Number.parseFloat(priceBYN),
      description: description ? String(description) : null,
    },
  });
  res.redirect(`/admin/services?token=${encodeURIComponent(String(req.query.token ?? ''))}`);
});

// Удалить
app.post('/admin/services/:id/delete', requireAdmin, async (req: Request, res: Response) => {
  const id = Number.parseInt(req.params.id);
  await prisma.service.delete({ where: { id } });
  res.redirect(`/admin/services?token=${encodeURIComponent(String(req.query.token ?? ''))}`);
});

// ===============================
// Главная (простая страница-демо)
// ===============================
app.get('/', (_req: Request, res: Response) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8').send(`<!doctype html>
<html lang="ru"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Онлайн-запись</title></head>
<body style="font:14px/1.4 system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;padding:24px">
  <h1>Онлайн-запись</h1>
  <p>Это простая статика мини-приложения (без сборки). Сервер: Express + Prisma.</p>
  <p>
    <a href="/app.html">Открыть мини-приложение</a>
  </p>
  <p>
    <a href="/admin/services">Админка (нужен ?token=...)</a>
  </p>
  <hr/>
  <p><a href="/api/services" target="_blank">Показать услуги (GET /api/services)</a></p>
</body></html>`);
});

// ===============================
// Запуск + установка Telegram webhook (асинхронно)
// ===============================
const port = Number(process.env.PORT || 8080);

app.listen(port, async () => {
  console.log(`[http] listening on :${port}`);
  try {
    await installWebhook(app);
  } catch (err) {
    console.error('[tg] setWebhook failed', err);
  }
});

// ===============================
// Утилиты для HTML
// ===============================
function escapeHtml(s: string): string {
  return s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}
function escapeAttr(s: string): string {
  return escapeHtml(s).replaceAll("'", '&#39;');
}