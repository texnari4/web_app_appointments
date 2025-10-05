const TABS = ["masters","services","appointments","clients","reports","settings"];
const content = document.getElementById("content");
const title = document.getElementById("section-title");
const addBtn = document.getElementById("add-btn");
const navButtons = [...document.querySelectorAll("nav button")];
let current = "masters";

function setTab(name){
  current = name;
  title.textContent = ({masters:"Мастера",services:"Услуги",appointments:"Записи",clients:"Клиенты",reports:"Отчёты",settings:"Настройки"})[name];
  navButtons.forEach(b=>b.classList.toggle("active", b.dataset.tab===name));
  render();
}
navButtons.forEach(b=>b.addEventListener("click", ()=>setTab(b.dataset.tab)));
addBtn.addEventListener("click", ()=>{
  if(current==="masters") openMasterForm();
  if(current==="services") openServiceForm();
  if(current==="clients") openClientForm();
  if(current==="appointments") openAppointmentForm();
});

// --- Helpers
async function api(path, opts){
  const r = await fetch(path, Object.assign({headers:{"Content-Type":"application/json"}}, opts||{}));
  if(!r.ok) throw new Error(await r.text());
  return r.json();
}
function el(html){ const t = document.createElement("template"); t.innerHTML = html.trim(); return t.content.firstElementChild; }

// --- Masters
async function loadMasters(){ return api('/public/api/masters'); }
async function saveMaster(m){ return api('/public/api/masters', {method:'POST', body:JSON.stringify(m)}); }
async function updateMaster(id,m){ return api(`/public/api/masters/${id}`, {method:'PUT', body:JSON.stringify(m)}); }
async function deleteMaster(id){ return api(`/public/api/masters/${id}`, {method:'DELETE'}); }

function openMasterForm(existing){
  const data = existing || {name:"", phone:"", avatarUrl:"", isActive:true, description:"", specialties:[], schedule:{}};
  const wrap = el(`<div class="card"></div>`);
  wrap.innerHTML = `
    <div class="row" style="gap:12px; flex-wrap:wrap">
      <div style="flex:1 1 240px">
        <label>Имя</label>
        <input id="m-name" value="${data.name??""}"/>
      </div>
      <div style="flex:1 1 240px">
        <label>Телефон</label>
        <input id="m-phone" value="${data.phone??""}"/>
      </div>
      <div style="flex:1 1 240px">
        <label>Фото (URL)</label>
        <input id="m-avatar" value="${data.avatarUrl??""}"/>
      </div>
    </div>
    <div class="row" style="gap:12px">
      <div style="flex:1">
        <label>Специальности (через запятую)</label>
        <input id="m-spec" value="${(data.specialties||[]).join(', ')}"/>
      </div>
    </div>
    <div class="row" style="gap:8px; justify-content:flex-end; margin-top:12px">
      ${existing ? `<button class="btn" id="m-save">Сохранить</button>` : `<button class="btn" id="m-create">Создать</button>`}
    </div>
  `;
  content.prepend(wrap);
  wrap.querySelector('#m-create')?.addEventListener('click', async ()=>{
    const payload = {
      name: wrap.querySelector('#m-name').value.trim(),
      phone: wrap.querySelector('#m-phone').value.trim(),
      avatarUrl: wrap.querySelector('#m-avatar').value.trim(),
      isActive: true,
      specialties: wrap.querySelector('#m-spec').value.split(',').map(s=>s.trim()).filter(Boolean)
    };
    const {item} = await saveMaster(payload);
    const card = masterCard(item);
    content.querySelector('.grid')?.prepend(card);
    wrap.remove();
  });
  wrap.querySelector('#m-save')?.addEventListener('click', async ()=>{
    const payload = {
      name: wrap.querySelector('#m-name').value.trim(),
      phone: wrap.querySelector('#m-phone').value.trim(),
      avatarUrl: wrap.querySelector('#m-avatar').value.trim(),
      isActive: true,
      specialties: wrap.querySelector('#m-spec').value.split(',').map(s=>s.trim()).filter(Boolean)
    };
    const {item} = await updateMaster(existing.id, payload);
    const old = document.querySelector(`[data-id="${existing.id}"]`);
    const fresh = masterCard(item);
    old.replaceWith(fresh);
    wrap.remove();
  });
}
function masterCard(m){
  const node = el(`
    <div class="card" data-id="${m.id}">
      <div class="row" style="justify-content:space-between">
        <div class="row" style="gap:12px">
          <img src="${m.avatarUrl||'https://placehold.co/48x48'}" alt="" width="48" height="48" style="border-radius:12px; object-fit:cover"/>
          <div>
            <div style="font-weight:700">${m.name}</div>
            <div class="muted">${m.phone||''}</div>
          </div>
        </div>
        <div class="row" style="gap:6px">
          <button class="btn" data-act="edit">Редактировать</button>
          <button class="btn btn-danger" data-act="del">Удалить</button>
        </div>
      </div>
    </div>
  `);
  node.querySelector('[data-act="del"]').addEventListener('click', async ()=>{
    if(!confirm('Удалить мастера?')) return;
    await deleteMaster(m.id);
    node.remove();
  });
  node.querySelector('[data-act="edit"]').addEventListener('click', ()=> openMasterForm(m));
  return node;
}

// --- Services placeholder (UI only)
function renderServices(){ content.innerHTML = `<div class="card">Секции «Услуги», «Записи», «Клиенты», «Отчёты» доступны в API, UI будет пополняться в следующих коммитах.</div>`; }

async function renderMasters(){
  content.innerHTML = `<div class="grid" id="masters-grid"></div>`;
  const grid = document.getElementById('masters-grid');
  const {items} = await loadMasters();
  for(const m of items){
    grid.appendChild(masterCard(m));
  }
}

async function render(){
  if(current==="masters") return renderMasters();
  if(current==="services"||current==="appointments"||current==="clients"||current==="reports"||current==="settings") return renderServices();
}

setTab("masters");
