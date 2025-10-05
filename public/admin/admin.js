const api = {
  masters: '/public/api/masters',
  services: '/public/api/services',
  clients: '/public/api/clients',
  appointments: '/public/api/appointments',
  reports: '/public/api/reports/summary',
  settings: '/public/api/settings'
};

const tabs = document.querySelectorAll('.tabs button');
const sections = document.querySelectorAll('.tab');
tabs.forEach(btn => btn.addEventListener('click', ()=>{
  tabs.forEach(b=>b.classList.remove('active'));
  sections.forEach(s=>s.classList.remove('active'));
  btn.classList.add('active');
  document.getElementById(btn.dataset.tab).classList.add('active');
  loadTab(btn.dataset.tab);
}));

async function jsonGET(url){
  const r = await fetch(url); if(!r.ok) throw new Error('GET '+url); return r.json();
}
async function jsonPOST(url, body){
  const r = await fetch(url,{method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)});
  if(!r.ok) throw new Error('POST '+url); return r.json();
}
async function jsonPUT(url, body){
  const r = await fetch(url,{method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)});
  if(!r.ok) throw new Error('PUT '+url); return r.json();
}
async function jsonDELETE(url){
  const r = await fetch(url,{method:'DELETE'}); if(!r.ok) throw new Error('DELETE '+url); return r.json();
}

function el(html){ const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; }
function wrapCard(title, content){
  return el(`<div class="card"><div class="row"><h3>${title}</h3></div>${content}</div>`);
}

async function loadTab(name){
  if(name==='masters') return renderMasters();
  if(name==='services') return renderServices();
  if(name==='clients') return renderClients();
  if(name==='appointments') return renderAppointments();
  if(name==='reports') return renderReports();
  if(name==='settings') return renderSettings();
}

// --- Masters
async function renderMasters(){
  const root = document.getElementById('masters'); root.innerHTML='';
  const data = await jsonGET(api.masters);
  const card = wrapCard('Мастера', `<div class="toolbar">
      <form id="fm-master" class="create-form">
        <input name="name" placeholder="Имя" required>
        <input name="phone" placeholder="Телефон" required>
        <input name="avatarUrl" placeholder="Фото URL">
        <button class="btn" type="submit">Добавить</button>
      </form>
    </div>
    <ul class="items" id="list-masters"></ul>`);
  root.append(card);

  const list = card.querySelector('#list-masters');
  const renderItem = (m) => {
    const li = el(`<li class="item">
        <div class="row"><strong>${m.name}</strong><span class="muted">${m.isActive?'активен':'скрыт'}</span></div>
        <div class="muted">${m.phone}</div>
        <label>Специальности</label>
        <input value="${(m.specialties||[]).join(', ')}" data-k="specialties">
        <label>Описание</label>
        <textarea data-k="description">${m.description||''}</textarea>
        <div class="row">
          <button class="btn secondary" data-act="save">Сохранить</button>
          <button class="btn danger" data-act="del">Удалить</button>
        </div>
    </li>`);
    li.querySelector('[data-act="save"]').onclick = async () => {
      const payload = {
        specialties: li.querySelector('[data-k="specialties"]').value.split(',').map(s=>s.trim()).filter(Boolean),
        description: li.querySelector('[data-k="description"]').value
      };
      const updated = await jsonPUT(`${api.masters}/${m.id}`, payload);
      Object.assign(m, updated);
    };
    li.querySelector('[data-act="del"]').onclick = async () => {
      await jsonDELETE(`${api.masters}/${m.id}`);
      li.remove();
    };
    return li;
  };
  data.items.forEach(m=>list.append(renderItem(m)));

  card.querySelector('#fm-master').onsubmit = async (e)=>{
    e.preventDefault();
    const f = e.target;
    const payload = { name:f.name.value.trim(), phone:f.phone.value.trim(), avatarUrl:f.avatarUrl.value.trim()||undefined };
    const created = await jsonPOST(api.masters, payload);
    list.prepend(renderItem(created));
    f.reset();
  };
}

// --- Services
async function renderServices(){
  const root = document.getElementById('services'); root.innerHTML='';
  const data = await jsonGET(api.services);
  const card = wrapCard('Услуги', `<div class="toolbar">
      <form id="fm-service" class="create-form">
        <input name="name" placeholder="Название" required>
        <input name="price" type="number" placeholder="Цена" required>
        <input name="durationMin" type="number" placeholder="Длительность (мин)" required>
        <button class="btn" type="submit">Добавить</button>
      </form>
    </div>
    <ul class="items" id="list-services"></ul>`);
  root.append(card);
  const list = card.querySelector('#list-services');

  const renderItem = (s) => {
    const li = el(`<li class="item">
      <div class="row"><strong>${s.name}</strong><span class="muted">${s.durationMin} мин · ${s.price}₽</span></div>
      <label>Описание</label>
      <textarea data-k="description">${s.description||''}</textarea>
      <div class="row">
        <button class="btn secondary" data-act="save">Сохранить</button>
        <button class="btn danger" data-act="del">Удалить</button>
      </div>
    </li>`);
    li.querySelector('[data-act="save"]').onclick = async () => {
      const payload = { description: li.querySelector('[data-k="description"]').value };
      const updated = await jsonPUT(`${api.services}/${s.id}`, payload);
      Object.assign(s, updated);
    };
    li.querySelector('[data-act="del"]').onclick = async () => {
      await jsonDELETE(`${api.services}/${s.id}`);
      li.remove();
    };
    return li;
  };
  data.items.forEach(s=>list.append(renderItem(s)));

  card.querySelector('#fm-service').onsubmit = async (e)=>{
    e.preventDefault();
    const f = e.target;
    const payload = { name:f.name.value.trim(), price:Number(f.price.value), durationMin:Number(f.durationMin.value) };
    const created = await jsonPOST(api.services, payload);
    list.prepend(renderItem(created));
    f.reset();
  };
}

// --- Clients
async function renderClients(){
  const root = document.getElementById('clients'); root.innerHTML='';
  const data = await jsonGET(api.clients);
  const card = wrapCard('Клиенты', `<div class="toolbar">
      <form id="fm-client" class="create-form">
        <input name="name" placeholder="Имя" required>
        <input name="phone" placeholder="Телефон" required>
        <button class="btn" type="submit">Добавить</button>
      </form>
    </div>
    <ul class="items" id="list-clients"></ul>`);
  root.append(card);
  const list = card.querySelector('#list-clients');

  const renderItem = (c) => {
    const li = el(`<li class="item">
      <div class="row"><strong>${c.name}</strong><span class="muted">${c.phone}</span></div>
      <label>Заметка</label>
      <textarea data-k="note">${c.note||''}</textarea>
      <div class="row">
        <button class="btn secondary" data-act="save">Сохранить</button>
        <button class="btn danger" data-act="del">Удалить</button>
      </div>
    </li>`);
    li.querySelector('[data-act="save"]').onclick = async ()=>{
      const payload = { note: li.querySelector('[data-k="note"]').value };
      const updated = await jsonPUT(`${api.clients}/${c.id}`, payload);
      Object.assign(c, updated);
    };
    li.querySelector('[data-act="del"]').onclick = async ()=>{
      await jsonDELETE(`${api.clients}/${c.id}`);
      li.remove();
    };
    return li;
  };
  data.items.forEach(c=>list.append(renderItem(c)));

  card.querySelector('#fm-client').onsubmit = async (e)=>{
    e.preventDefault();
    const f = e.target;
    const created = await jsonPOST(api.clients, { name:f.name.value.trim(), phone:f.phone.value.trim() });
    list.prepend(renderItem(created));
    f.reset();
  };
}

// --- Appointments
async function renderAppointments(){
  const root = document.getElementById('appointments'); root.innerHTML='';
  const [masters, services, clients, apis] = await Promise.all([
    jsonGET(api.masters), jsonGET(api.services), jsonGET(api.clients), jsonGET(api.appointments)
  ]);

  const card = wrapCard('Записи', `<div class="toolbar">
    <form id="fm-appointment" class="create-form">
      <select name="masterId" required>${masters.items.map(m=>`<option value="${m.id}">${m.name}</option>`).join('')}</select>
      <select name="clientId" required>${clients.items.map(c=>`<option value="${c.id}">${c.name}</option>`).join('')}</select>
      <select name="serviceId" required>${services.items.map(s=>`<option value="${s.id}">${s.name}</option>`).join('')}</select>
      <input name="startISO" type="datetime-local" required>
      <input name="endISO" type="datetime-local" required>
      <button class="btn" type="submit">Создать</button>
    </form>
  </div>
  <ul class="items" id="list-appointments"></ul>`);
  root.append(card);
  const list = card.querySelector('#list-appointments');

  const dict = {
    master: Object.fromEntries(masters.items.map(m=>[m.id, m.name])),
    service: Object.fromEntries(services.items.map(s=>[s.id, `${s.name} · ${s.price}₽`])),
    client: Object.fromEntries(clients.items.map(c=>[c.id, `${c.name} (${c.phone})`]))
  };

  const renderItem = (a) => {
    const li = el(`<li class="item">
      <div class="row"><strong>${dict.client[a.clientId]}</strong><span class="muted">${new Date(a.startISO).toLocaleString()}</span></div>
      <div class="muted">${dict.master[a.masterId]} • ${dict.service[a.serviceId]}</div>
      <label>Статус</label>
      <select data-k="status">
        ${['scheduled','completed','canceled'].map(s=>`<option ${s===a.status?'selected':''}>${s}</option>`).join('')}
      </select>
      <div class="row">
        <button class="btn secondary" data-act="save">Сохранить</button>
        <button class="btn danger" data-act="del">Удалить</button>
      </div>
    </li>`);
    li.querySelector('[data-act="save"]').onclick = async ()=>{
      const payload = { status: li.querySelector('[data-k="status"]').value };
      const updated = await jsonPUT(`${api.appointments}/${a.id}`, payload);
      Object.assign(a, updated);
    };
    li.querySelector('[data-act="del"]').onclick = async ()=>{
      await jsonDELETE(`${api.appointments}/${a.id}`);
      li.remove();
    };
    return li;
  };

  apis.items.forEach(a=>list.append(renderItem(a)));

  card.querySelector('#fm-appointment').onsubmit = async (e)=>{
    e.preventDefault();
    const f = e.target;
    const payload = {
      masterId:f.masterId.value, clientId:f.clientId.value, serviceId:f.serviceId.value,
      startISO:new Date(f.startISO.value).toISOString(), endISO:new Date(f.endISO.value).toISOString()
    };
    const created = await jsonPOST(api.appointments, payload);
    list.prepend(renderItem(created));
    f.reset();
  };
}

// --- Reports
async function renderReports(){
  const root = document.getElementById('reports'); root.innerHTML='';
  const card = wrapCard('Отчёты', `<div class="toolbar">
    <form id="fm-report" class="create-form">
      <input name="from" type="date">
      <input name="to" type="date">
      <button class="btn" type="submit">Показать</button>
    </form>
  </div>
  <div id="report-content"></div>`);
  root.append(card);
  const out = card.querySelector('#report-content');

  async function run(params={}){
    const q = new URLSearchParams(params).toString();
    const data = await jsonGET(api.reports + (q?`?${q}`:''));
    out.innerHTML = `<div class="item">
      <div><strong>Всего записей:</strong> ${data.count}</div>
      <div><strong>Выручка:</strong> ${data.revenue}₽</div>
      <div><strong>Топ услуг:</strong><br>${data.popular.map(p=>`${p.name} — ${p.count}`).join('<br>')}</div>
    </div>`;
  }

  card.querySelector('#fm-report').onsubmit = (e)=>{
    e.preventDefault();
    const f = e.target;
    const params = {};
    if (f.from.value) params.from = new Date(f.from.value).toISOString();
    if (f.to.value) params.to = new Date(f.to.value).toISOString();
    run(params);
  };

  run();
}

// --- Settings
async function renderSettings(){
  const root = document.getElementById('settings'); root.innerHTML='';
  const st = await jsonGET(api.settings);
  const card = wrapCard('Настройки', `<div class="item">
    <label>Название бизнеса</label>
    <input id="businessName" value="${st.businessName||''}">
    <label>Часовой пояс (IANA)</label>
    <input id="timezone" value="${st.timezone||'UTC'}">
    <label>Часы работы по умолчанию</label>
    <div class="row">
      <input id="wh-from" placeholder="09:00" value="${(st.workHoursDefault&&st.workHoursDefault.from)||'09:00'}">
      <input id="wh-to" placeholder="18:00" value="${(st.workHoursDefault&&st.workHoursDefault.to)||'18:00'}">
    </div>
    <div class="row" style="margin-top:10px">
      <button class="btn" id="save">Сохранить</button>
    </div>
  </div>`);
  root.append(card);
  card.querySelector('#save').onclick = async ()=>{
    const payload = {
      businessName: document.getElementById('businessName').value,
      timezone: document.getElementById('timezone').value,
      workHoursDefault: {
        from: document.getElementById('wh-from').value,
        to: document.getElementById('wh-to').value
      }
    };
    await jsonPUT(api.settings, payload);
  };
}

// initial
loadTab('masters');
