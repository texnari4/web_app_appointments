const api = {
  async jsonGET(url){ const r = await fetch(url); if(!r.ok) throw new Error(`GET ${url}`); return r.json(); },
  async jsonPOST(url, body){ const r = await fetch(url,{method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)}); if(!r.ok) throw new Error(`POST ${url}`); return r.json(); },
  async jsonPUT(url, body){ const r = await fetch(url,{method:'PUT', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)}); if(!r.ok) throw new Error(`PUT ${url}`); return r.json(); },
  async del(url){ const r = await fetch(url,{method:'DELETE'}); if(!r.ok) throw new Error(`DELETE ${url}`); return true; }
};

function el(html){ const t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstElementChild; }

async function renderMasters(root){
  const container = el(`<div class="container">
    <div class="card">
      <h2>Добавить мастера</h2>
      <div class="grid">
        <div><label>Имя</label><input id="m-name"/></div>
        <div><label>Телефон</label><input id="m-phone"/></div>
        <div><label>Аватар URL</label><input id="m-avatar"/></div>
      </div>
      <div style="margin-top:12px"><button class="btn" id="m-save">Сохранить</button></div>
    </div>
    <div class="card"><h2>Список мастеров</h2><div class="list" id="m-list"></div></div>
  </div>`);
  root.replaceChildren(container);

  async function reload(){
    const data = await api.jsonGET('/public/api/masters');
    const list = container.querySelector('#m-list');
    list.innerHTML = '';
    data.items.forEach(it => {
      list.appendChild(el(`<div class="item"><div>
        <div><strong>${it.name}</strong></div>
        <div class="small">${it.phone}</div></div>
        <div class="row"><button class="btn secondary" data-del="${it.id}">Удалить</button></div>
      </div>`));
    });
  }

  container.querySelector('#m-save').addEventListener('click', async ()=>{
    await api.jsonPOST('/public/api/masters', {
      name: container.querySelector('#m-name').value,
      phone: container.querySelector('#m-phone').value,
      avatarUrl: container.querySelector('#m-avatar').value,
      isActive: true
    });
    await reload();
  });
  container.addEventListener('click', async (e)=>{
    const t = e.target;
    if(t instanceof HTMLElement && t.dataset.del){
      await api.del(`/public/api/masters/${t.dataset.del}`);
      await reload();
    }
  });
  await reload();
}

async function renderServices(root){
  const container = el(`<div class="container">
    <div class="card">
      <h2>Группа услуг</h2>
      <div class="row">
        <input id="g-title" placeholder="Название группы"/>
        <button class="btn" id="g-add">Добавить группу</button>
      </div>
    </div>
    <div class="card">
      <h2>Добавить услугу</h2>
      <div class="grid">
        <div><label>Группа</label><select id="s-group"></select></div>
        <div><label>Название</label><input id="s-title"/></div>
        <div><label>Цена</label><input id="s-price" type="number" min="0"/></div>
        <div><label>Длительность (мин)</label><input id="s-dur" type="number" min="5" step="5"/></div>
        <div class="grid" style="grid-template-columns:1fr">
          <label>Описание</label><textarea id="s-desc" rows="3"></textarea>
        </div>
      </div>
      <div style="margin-top:12px"><button class="btn" id="s-save">Сохранить услугу</button></div>
    </div>
    <div class="card"><h2>Список услуг</h2><div class="list" id="s-list"></div></div>
  </div>`);
  root.replaceChildren(container);

  async function loadGroups(){
    const {items} = await api.jsonGET('/public/api/service-groups');
    const sel = container.querySelector('#s-group');
    sel.innerHTML = items.map((g)=>`<option value="${g.id}">${g.title}</option>`).join('');
  }
  async function reloadServices(){
    const {items} = await api.jsonGET('/public/api/services');
    const list = container.querySelector('#s-list');
    const groups = (await api.jsonGET('/public/api/service-groups')).items;
    const gMap = Object.fromEntries(groups.map(g=>[g.id,g.title]));
    list.innerHTML = '';
    items.forEach(s=>{
      list.appendChild(el(`<div class="item">
        <div>
          <div><strong>${s.title}</strong> <span class="small">/ ${gMap[s.groupId]||'—'}</span></div>
          <div class="small">${s.durationMin} мин • ${s.price} BYN</div>
        </div>
        <div class="row">
          <button class="btn secondary" data-del="${s.id}">Удалить</button>
        </div>
      </div>`));
    });
  }

  container.querySelector('#g-add').addEventListener('click', async ()=>{
    const title = container.querySelector('#g-title').value.trim();
    if(!title) return;
    await api.jsonPOST('/public/api/service-groups', { title });
    container.querySelector('#g-title').value='';
    await loadGroups();
  });

  container.querySelector('#s-save').addEventListener('click', async ()=>{
    const groupId = container.querySelector('#s-group').value;
    const title = container.querySelector('#s-title').value;
    const price = Number(container.querySelector('#s-price').value);
    const durationMin = Number(container.querySelector('#s-dur').value);
    const description = container.querySelector('#s-desc').value;
    await api.jsonPOST('/public/api/services', { groupId, title, price, durationMin, description });
    await reloadServices();
  });

  container.addEventListener('click', async (e)=>{
    const t = e.target;
    if(t instanceof HTMLElement && t.dataset.del){
      await api.del(`/public/api/services/${t.dataset.del}`);
      await reloadServices();
    }
  });

  await loadGroups();
  await reloadServices();
}

async function loadTab(tab){
  const root = document.getElementById('app');
  if(tab==='services') return renderServices(root);
  return renderMasters(root);
}

document.addEventListener('DOMContentLoaded', ()=>{
  document.querySelectorAll('.tabs button').forEach(btn=>{
    btn.addEventListener('click', ()=> loadTab(btn.dataset.tab));
  });
  loadTab('masters');
});
