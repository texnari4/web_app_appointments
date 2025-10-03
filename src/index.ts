
import express from 'express';
import cors from 'cors';
import { PrismaClient } from '@prisma/client';
import { tgRouter, installWebhook } from './telegram';

const prisma = new PrismaClient();
const app = express();

app.use(cors());
app.use(express.json());

// --- Root info page ---
app.get('/', (_req, res) => {
  res.type('html').send(`<!doctype html>
  <html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Онлайн‑запись — статус</title>
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Inter,Helvetica,Arial,sans-serif;line-height:1.5;margin:24px;color:#0b0b0f}
      code{background:#f4f5f7;padding:2px 6px;border-radius:6px}
      .wrap{max-width:960px;margin:0 auto}
      ul{margin:8px 0 24px 18px}
      .ok{color:#16a34a;font-weight:600}
      a{color:#2563eb;text-decoration:none}
      a:hover{text-decoration:underline}
    </style>
  </head>
  <body>
    <div class="wrap">
      <h1>Онлайн‑запись</h1>
      <p>Сервер: <b>Express + Prisma</b></p>
      <p class="ok">Сервис запущен ✔︎</p>
      <h3>Публичные API</h3>
      <ul>
        <li><code>GET /api/services</code></li>
        <li><code>POST /api/appointments</code></li>
      </ul>
      <h3>Админ API</h3>
      <ul>
        <li><code>GET /admin/api/services</code></li>
        <li><code>POST /admin/api/services</code></li>
        <li><code>PUT /admin/api/services/:id</code></li>
        <li><code>DELETE /admin/api/services/:id</code></li>
      </ul>
      <h3>UI</h3>
      <ul>
        <li><a href="/app">/app</a> — простая витрина клиента</li>
        <li><a href="/admin/services">/admin/services</a> — страница редактирования услуг</li>
      </ul>
    </div>
  </body>
  </html>`);
});

// --- Simple client-facing demo page ---
app.get('/app', (_req, res) => {
  res.type('html').send(`<!doctype html>
  <html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Онлайн‑запись — клиент</title>
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Inter,Helvetica,Arial,sans-serif;line-height:1.5;margin:20px;color:#0b0b0f}
      .card{max-width:720px;margin:0 auto;padding:16px 20px;border:1px solid #e5e7eb;border-radius:14px;box-shadow:0 2px 8px rgba(0,0,0,.04)}
      button{border:0;border-radius:999px;padding:10px 16px;font-weight:600;cursor:pointer;background:#0ea5e9;color:white}
      button:disabled{opacity:.5;cursor:not-allowed}
      pre{background:#0b1220;color:#e5e7eb;padding:12px;border-radius:12px;overflow:auto}
    </style>
  </head>
  <body>
    <div class="card">
      <h2>Витрина клиента</h2>
      <p>Нажмите, чтобы получить список услуг (демо):</p>
      <p><button id="btn">Показать услуги</button></p>
      <pre id="out" aria-live="polite">Жду запроса…</pre>
    </div>
    <script>
      const btn = document.getElementById('btn');
      const out = document.getElementById('out');
      btn.onclick = async () => {
        btn.disabled = true;
        out.textContent = 'Загрузка…';
        try{
          const r = await fetch('/api/services');
          const j = await r.json();
          out.textContent = JSON.stringify(j, null, 2);
        }catch(e){
          out.textContent = 'Ошибка: ' + (e?.message || e);
        }finally{
          btn.disabled = false;
        }
      };
    </script>
  </body>
  </html>`);
});

// --- Admin UI page (no extra deps; uses fetch to our Admin API) ---
app.get('/admin/services', (_req, res) => {
  res.type('html').send(`<!doctype html>
  <html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Админка — услуги</title>
    <style>
      :root{--ink:#0b0b0f;--muted:#6b7280;--line:#e5e7eb;--bg:#ffffff;--brand:#2563eb}
      *{box-sizing:border-box}
      body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Inter,Helvetica,Arial,sans-serif;margin:0;background:var(--bg);color:var(--ink)}
      header{position:sticky;top:0;background:#fff;border-bottom:1px solid var(--line);padding:12px 20px}
      main{max-width:980px;margin:0 auto;padding:20px}
      h1{font-size:20px;margin:0}
      .row{display:flex;gap:12px;flex-wrap:wrap}
      .card{border:1px solid var(--line);border-radius:16px;padding:16px}
      .grow{flex:1 1 420px}
      input,textarea{width:100%;padding:10px;border:1px solid var(--line);border-radius:12px;font:inherit}
      label{font-size:12px;color:var(--muted)}
      .grid{display:grid;grid-template-columns:1fr auto auto auto;gap:8px;align-items:center}
      .grid > div, .grid > span{padding:8px;border-bottom:1px solid var(--line)}
      .head{font-weight:600;background:#f8fafc}
      button{border:0;border-radius:999px;padding:8px 14px;font-weight:600;cursor:pointer}
      .primary{background:var(--brand);color:#fff}
      .ghost{background:#f3f4f6}
      .danger{background:#ef4444;color:#fff}
      .muted{color:var(--muted)}
      .row > *{min-width:280px}
      .right{display:flex;gap:8px;justify-content:flex-end}
      .mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}
    </style>
  </head>
  <body>
    <header><h1>Админка · Услуги</h1></header>
    <main>
      <div class="row">
        <section class="card grow">
          <h3>Добавить / обновить</h3>
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
            <div><label>ID (для обновления)</label><input id="id" placeholder="оставьте пустым для создания"></div>
            <div><label>Название</label><input id="name" required></div>
            <div><label>Длительность (мин)</label><input id="duration" type="number" min="5" step="5" required></div>
            <div><label>Цена (BYN)</label><input id="price" type="number" min="0" step="0.01" required></div>
            <div style="grid-column:1/-1"><label>Описание</label><textarea id="desc" rows="3"></textarea></div>
          </div>
          <div class="right" style="margin-top:12px">
            <button class="ghost" id="reset">Очистить</button>
            <button class="primary" id="save">Сохранить</button>
          </div>
        </section>
        <aside class="card" style="width:280px">
          <div class="muted">Подсказка</div>
          <p class="muted">Эта страница работает поверх API:
          <span class="mono">/admin/api/services</span>. Для продвинутой
          админки позже подключим полноценный UI.</p>
        </aside>
      </div>

      <section class="card" style="margin-top:16px">
        <h3>Список услуг</h3>
        <div class="grid head">
          <div>Название</div><span>Длит.</span><span>Цена</span><span></span>
        </div>
        <div id="rows" class="grid"></div>
      </section>
    </main>
    <script>
      const $ = (id)=>document.getElementById(id);
      const rows = $('rows');
      const id = $('id'), name = $('name'), duration = $('duration'), price = $('price'), desc = $('desc');
      const reset = $('reset'), save = $('save');

      function formatBynFromCents(cents){ return (cents/100).toFixed(2); }
      function toCents(byn){ return Math.round(parseFloat(String(byn || 0).replace(',','.'))*100); }

      async function load(){
        rows.innerHTML = '<span class="muted" style="grid-column:1/-1;padding:16px">Загрузка…</span>';
        const res = await fetch('/admin/api/services');
        const data = await res.json();
        rows.innerHTML='';
        data.forEach(s => addRow(s));
      }

      function addRow(s){
        const name = document.createElement('div');
        name.textContent = s.name;

        const dur = document.createElement('span');
        dur.textContent = s.durationMin + ' мин';

        const price = document.createElement('span');
        price.textContent = formatBynFromCents(s.priceCents) + ' BYN';

        const actions = document.createElement('span');
        actions.style.display='flex'; actions.style.gap='6px'; actions.style.justifyContent='flex-end';

        const edit = document.createElement('button');
        edit.className = 'ghost'; edit.textContent = 'Редактировать';
        edit.onclick = ()=>{
          $('id').value = s.id;
          $('name').value = s.name;
          $('duration').value = s.durationMin;
          $('price').value = formatBynFromCents(s.priceCents);
          $('desc').value = s.description || '';
          window.scrollTo({top:0,behavior:'smooth'});
        };

        const del = document.createElement('button');
        del.className = 'danger'; del.textContent = 'Удалить';
        del.onclick = async()=>{
          if(!confirm('Удалить услугу «'+s.name+'»?')) return;
          const r = await fetch('/admin/api/services/'+encodeURIComponent(s.id), { method:'DELETE' });
          if(r.ok) load(); else alert('Ошибка удаления');
        };

        actions.append(edit, del);

        rows.append(name, dur, price, actions);
      }

      reset.onclick = () => { id.value=''; name.value=''; duration.value=''; price.value=''; desc.value=''; };

      save.onclick = async () => {
        const payload:any = {
          name: name.value.trim(),
          durationMin: parseInt(duration.value, 10),
          priceCents: toCents(price.value),
          description: desc.value.trim() || null
        };
        if(!payload.name || !payload.durationMin || Number.isNaN(payload.priceCents)){
          alert('Заполните корректно все поля.');
          return;
        }
        if(id.value){
          const r = await fetch('/admin/api/services/'+encodeURIComponent(id.value), {
            method:'PUT', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload)
          });
          if(!r.ok){ alert('Ошибка сохранения'); return; }
        }else{
          const r = await fetch('/admin/api/services', {
            method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload)
          });
          if(!r.ok){ alert('Ошибка создания'); return; }
        }
        reset.click(); load();
      };

      load();
    </script>
  </body>
  </html>`);
});

// --- Public API: list services ---
app.get('/api/services', async (_req, res) => {
  try{
    const services = await prisma.service.findMany({
      orderBy: [{ name: 'asc' }],
      select: { id:true, name:true, durationMin:true, priceCents:true, description:true, createdAt:true, updatedAt:true }
    });
    res.json(services);
  }catch(err:any){
    res.status(500).json({ status: 'error', message: err?.message || 'Internal error' });
  }
});

// --- Public API: create appointment ---
app.post('/api/appointments', async (req, res) => {
  try{
    const { serviceId, staffId, startAt, client } = req.body || {};
    if(!serviceId || !staffId || !startAt){
      return res.status(400).json({ status:'error', message:'serviceId, staffId, startAt обязательны' });
    }
    const start = new Date(startAt);
    if(Number.isNaN(start.getTime())){
      return res.status(400).json({ status:'error', message:'Некорректный startAt' });
    }
    const service = await prisma.service.findUnique({ where: { id: String(serviceId) } });
    if(!service) return res.status(404).json({ status:'error', message:'Услуга не найдена' });

    const end = new Date(start.getTime() + service.durationMin * 60000);

    // find or create client by tgUserId (if provided)
    let clientConnect = undefined;
    if(client?.tgUserId){
      const existing = await prisma.client.findFirst({ where: { tgUserId: String(client.tgUserId) } });
      if(existing){
        clientConnect = { connect: { id: existing.id } };
      }else{
        clientConnect = {
          create: {
            tgUserId: String(client.tgUserId),
            firstName: client.firstName ?? null,
            lastName: client.lastName ?? null,
            phoneEnc: null,
            emailEnc: null
          }
        };
      }
    }

    const created = await prisma.appointment.create({
      data: {
        startAt: start,
        endAt: end,
        status: 'CREATED',
        service: { connect: { id: String(serviceId) } },
        staff:   { connect: { id: String(staffId) } },
        ...(clientConnect ? { client: clientConnect } : {}),
      },
      include: {
        service: true,
        staff: true,
        client: true
      }
    });

    res.status(201).json(created);
  }catch(err:any){
    res.status(500).json({ status: 'error', message: err?.message || 'Internal error' });
  }
});

// --- Admin API: Services CRUD ---
app.get('/admin/api/services', async (_req, res) => {
  try{
    const list = await prisma.service.findMany({ orderBy:[{ name:'asc' }] });
    res.json(list);
  }catch(err:any){
    res.status(500).json({ status:'error', message: err?.message || 'Internal error' });
  }
});

app.post('/admin/api/services', async (req, res) => {
  try{
    const { name, durationMin, priceCents, description } = req.body || {};
    if(!name || !durationMin || typeof priceCents !== 'number'){
      return res.status(400).json({ status:'error', message:'name, durationMin, priceCents обязательны' });
    }
    const created = await prisma.service.create({
      data: { name: String(name), durationMin: Number(durationMin), priceCents: Number(priceCents), description: description ?? null }
    });
    res.status(201).json(created);
  }catch(err:any){
    res.status(500).json({ status:'error', message: err?.message || 'Internal error' });
  }
});

app.put('/admin/api/services/:id', async (req, res) => {
  try{
    const { id } = req.params;
    const { name, durationMin, priceCents, description } = req.body || {};
    const updated = await prisma.service.update({
      where: { id: String(id) },
      data: {
        ...(name !== undefined ? { name: String(name) } : {}),
        ...(durationMin !== undefined ? { durationMin: Number(durationMin) } : {}),
        ...(priceCents !== undefined ? { priceCents: Number(priceCents) } : {}),
        ...(description !== undefined ? { description: description } : {}),
      }
    });
    res.json(updated);
  }catch(err:any){
    res.status(500).json({ status:'error', message: err?.message || 'Internal error' });
  }
});

app.delete('/admin/api/services/:id', async (req, res) => {
  try{
    const { id } = req.params;
    await prisma.service.delete({ where: { id: String(id) } });
    res.status(204).send();
  }catch(err:any){
    res.status(500).json({ status:'error', message: err?.message || 'Internal error' });
  }
});

// --- Telegram ---
app.use('/tg', tgRouter);

// --- Bootstrap ---
const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const PUBLIC_BASE_URL = process.env.RAILWAY_URL || process.env.PUBLIC_BASE_URL || '';

app.listen(PORT, async () => {
  console.log(`[http] listening on :${PORT}`);
  if (PUBLIC_BASE_URL) {
    try {
      await installWebhook(new URL('/tg/webhook', PUBLIC_BASE_URL).toString());
      console.log(`[tg] setWebhook OK → ${new URL('/tg/webhook', PUBLIC_BASE_URL).toString()}`);
    } catch (e:any) {
      console.error('[tg] setWebhook failed', e);
    }
  } else {
    console.log('[tg] skipped setWebhook — no PUBLIC_BASE_URL/RAILWAY_URL');
  }
});
