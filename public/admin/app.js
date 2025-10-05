const $ = (sel, root=document) => root.querySelector(sel);
const $$ = (sel, root=document) => [...root.querySelectorAll(sel)];

// Tabs
const tabs = $('#tabs');
const panes = $$('.pane');
tabs.addEventListener('click', (e) => {
  const btn = e.target.closest('button[data-tab]'); if(!btn) return;
  $$('#tabs button').forEach(b=>b.classList.toggle('active', b===btn));
  panes.forEach(p=>p.classList.toggle('active', p.dataset.pane===btn.dataset.tab));
  if (btn.dataset.tab === 'masters') loadMasters();
  if (btn.dataset.tab === 'services') loadServices();
  if (btn.dataset.tab === 'appointments') { fillFilters(); loadAppointments(); }
  if (btn.dataset.tab === 'clients') loadClients();
});

// ---- Masters ----
const mastersList = $('#mastersList');
const masterForm = $('#masterForm');

masterForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(masterForm);
  const body = {
    name: fd.get('name'),
    phone: fd.get('phone') || undefined,
    avatarUrl: fd.get('avatarUrl') || undefined,
    description: fd.get('description') || undefined,
    specialties: (fd.get('specialties') || '').toString().split(',').map(s=>s.trim()).filter(Boolean),
    isActive: fd.get('isActive') === 'on',
  };
  const res = await fetch('/public/api/masters',{ method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  if (!res.ok) return alert('Ошибка сохранения');
  const created = await res.json();
  masterForm.reset();
  prependMaster(created);
});

function masterCard(m){
  const el = document.createElement('div');
  el.className = 'card item';
  el.innerHTML = `
    <h4>${m.name}</h4>
    <div class="muted">${m.phone ?? ''}</div>
    <div class="row">
      ${(m.specialties||[]).map(s=>`<span class="pill">${s}</span>`).join('')}
    </div>
    <div class="actions">
      <button class="ok" data-act="edit">Редактировать</button>
      <button class="danger" data-act="del">Удалить</button>
    </div>
  `;
  el.querySelector('[data-act="del"]').addEventListener('click', async ()=>{
    if(!confirm('Удалить мастера?')) return;
    const res = await fetch(`/public/api/masters/${m.id}`,{ method:'DELETE' });
    if (res.ok) el.remove(); else alert('Ошибка удаления');
  });
  el.querySelector('[data-act="edit"]').addEventListener('click', async ()=>{
    const name = prompt('Имя', m.name); if(name==null) return;
    const phone = prompt('Телефон', m.phone ?? '') ?? undefined;
    const res = await fetch(`/public/api/masters/${m.id}`,{
      method:'PUT', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ name, phone })
    });
    if(res.ok){ const updated = await res.json(); el.replaceWith(masterCard(updated)); } else alert('Ошибка сохранения');
  });
  return el;
}
function prependMaster(m){ mastersList.prepend(masterCard(m)); }
async function loadMasters(){
  const res = await fetch('/public/api/masters'); const {items} = await res.json();
  mastersList.innerHTML = ''; items.forEach(m=>mastersList.appendChild(masterCard(m)));
}
loadMasters();

// ---- Services ----
const servicesList = $('#servicesList');
const serviceForm = $('#serviceForm');
serviceForm.addEventListener('submit', async (e)=>{
  e.preventDefault();
  const fd = new FormData(serviceForm);
  const body = {
    name: fd.get('name'),
    description: fd.get('description') || undefined,
    price: Number(fd.get('price') || 0),
    durationMin: Number(fd.get('durationMin') || 60),
    isActive: fd.get('isActive') === 'on',
  };
  const res = await fetch('/public/api/services',{ method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  if(!res.ok) return alert('Ошибка сохранения');
  const created = await res.json();
  serviceForm.reset();
  prependService(created);
});
function serviceCard(s){
  const el = document.createElement('div');
  el.className = 'card item';
  el.innerHTML = `
    <h4>${s.name}</h4>
    <div class="muted">${s.durationMin} мин — ${s.price}₽</div>
    <div class="actions">
      <button class="ok" data-act="edit">Редактировать</button>
      <button class="danger" data-act="del">Удалить</button>
    </div>
  `;
  el.querySelector('[data-act="del"]').addEventListener('click', async ()=>{
    if(!confirm('Удалить услугу?')) return;
    const res = await fetch(`/public/api/services/${s.id}`,{ method:'DELETE' });
    if (res.ok) el.remove(); else alert('Ошибка удаления');
  });
  el.querySelector('[data-act="edit"]').addEventListener('click', async ()=>{
    const name = prompt('Название', s.name); if(name==null) return;
    const price = Number(prompt('Цена', String(s.price ?? 0)) ?? 0);
    const durationMin = Number(prompt('Длительность (мин)', String(s.durationMin ?? 60)) ?? 60);
    const res = await fetch(`/public/api/services/${s.id}`,{
      method:'PUT', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ name, price, durationMin })
    });
    if(res.ok){ const updated = await res.json(); el.replaceWith(serviceCard(updated)); } else alert('Ошибка сохранения');
  });
  return el;
}
function prependService(s){ servicesList.prepend(serviceCard(s)); }
async function loadServices(){
  const res = await fetch('/public/api/services'); const {items} = await res.json();
  servicesList.innerHTML=''; items.forEach(s=>servicesList.appendChild(serviceCard(s)));
}

// ---- Clients ----
const clientsList = $('#clientsList');
const clientForm = $('#clientForm');
const clientSearch = $('#clientSearch');
$('#searchClient').addEventListener('click', ()=> loadClients(clientSearch.value || undefined));
clientForm.addEventListener('submit', async (e)=>{
  e.preventDefault();
  const fd = new FormData(clientForm);
  const body = {
    name: fd.get('name'),
    phone: fd.get('phone') || undefined,
    tg: fd.get('tg') || undefined,
    notes: fd.get('notes') || undefined,
  };
  const res = await fetch('/public/api/clients',{ method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  if(!res.ok) return alert('Ошибка сохранения');
  const created = await res.json();
  clientForm.reset();
  prependClient(created);
});
function clientCard(c){
  const el = document.createElement('div');
  el.className = 'card item';
  el.innerHTML = `
    <h4>${c.name}</h4>
    <div class="muted">${c.phone ?? ''} ${c.tg ? ' · '+c.tg : ''}</div>
    <div class="actions">
      <button class="ok" data-act="edit">Редактировать</button>
      <button class="danger" data-act="del">Удалить</button>
    </div>
  `;
  el.querySelector('[data-act="del"]').addEventListener('click', async ()=>{
    if(!confirm('Удалить клиента?')) return;
    const res = await fetch(`/public/api/clients/${c.id}`,{ method:'DELETE' });
    if (res.ok) el.remove(); else alert('Ошибка удаления');
  });
  el.querySelector('[data-act="edit"]').addEventListener('click', async ()=>{
    const name = prompt('Имя', c.name); if(name==null) return;
    const phone = prompt('Телефон', c.phone ?? '') ?? undefined;
    const res = await fetch(`/public/api/clients/${c.id}`,{
      method:'PUT', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ name, phone })
    });
    if(res.ok){ const updated = await res.json(); el.replaceWith(clientCard(updated)); } else alert('Ошибка сохранения');
  });
  return el;
}
function prependClient(c){ clientsList.prepend(clientCard(c)); }
async function loadClients(q){
  const url = new URL('/public/api/clients', location.origin);
  if (q) url.searchParams.set('q', q);
  const res = await fetch(url); const {items} = await res.json();
  clientsList.innerHTML=''; items.forEach(c=>clientsList.appendChild(clientCard(c)));
}

// ---- Appointments ----
const appointmentsList = $('#appointmentsList');
const filterMaster = $('#filterMaster');
const filterService = $('#filterService');
const filterClient = $('#filterClient');
const reloadAppointments = $('#reloadAppointments');

async function fillFilters(){
  filterMaster.innerHTML = '<option value="">Все мастера</option>';
  filterService.innerHTML = '<option value="">Все услуги</option>';
  filterClient.innerHTML = '<option value="">Все клиенты</option>';
  const [m,s,c] = await Promise.all([
    fetch('/public/api/masters').then(r=>r.json()),
    fetch('/public/api/services').then(r=>r.json()),
    fetch('/public/api/clients').then(r=>r.json()),
  ]);
  m.items.forEach(x=>filterMaster.insertAdjacentHTML('beforeend', `<option value="${x.id}">${x.name}</option>`));
  s.items.forEach(x=>filterService.insertAdjacentHTML('beforeend', `<option value="${x.id}">${x.name}</option>`));
  c.items.forEach(x=>filterClient.insertAdjacentHTML('beforeend', `<option value="${x.id}">${x.name}</option>`));
}

function appointmentCard(a){
  const el = document.createElement('div');
  el.className = 'card item';
  const start = new Date(a.start).toLocaleString();
  el.innerHTML = `
    <h4>Запись</h4>
    <div class="muted">${start}</div>
    <div class="row">
      <span class="pill">${a.status}</span>
    </div>
    <div class="actions">
      <button class="danger" data-act="del">Удалить</button>
    </div>
  `;
  el.querySelector('[data-act="del"]').addEventListener('click', async ()=>{
    if(!confirm('Удалить запись?')) return;
    const res = await fetch(`/public/api/appointments/${a.id}`,{ method:'DELETE' });
    if(res.ok) el.remove(); else alert('Ошибка удаления');
  });
  return el;
}
async function loadAppointments(){
  const url = new URL('/public/api/appointments', location.origin);
  const f = {
    masterId: filterMaster.value || undefined,
    serviceId: filterService.value || undefined,
    clientId: filterClient.value || undefined,
  };
  Object.entries(f).forEach(([k,v])=>{ if(v) url.searchParams.set(k,v); });
  const res = await fetch(url); const {items} = await res.json();
  appointmentsList.innerHTML=''; items.forEach(a=>appointmentsList.appendChild(appointmentCard(a)));
}
reloadAppointments.addEventListener('click', loadAppointments);

// ---- Reports ----
const repFrom = $('#repFrom'); const repTo = $('#repTo'); const reportOut = $('#reportOut');
$('#makeReport').addEventListener('click', async ()=>{
  const url = new URL('/public/api/reports', location.origin);
  if (repFrom.value) url.searchParams.set('from', new Date(repFrom.value).toISOString());
  if (repTo.value) url.searchParams.set('to', new Date(repTo.value).toISOString());
  const data = await fetch(url).then(r=>r.json());
  reportOut.textContent = JSON.stringify(data, null, 2);
});