// services.js
// Vanilla JS admin UI for Service Groups & Services
const API = {
  groups: '/public/api/service-groups',
  services: '/public/api/services',
};

// -- State
let state = {
  groups: [],
  currentGroupId: null,
  services: [],
  filters: {
    q: '',
    active: 'all',
  }
};

// -- Elements
const els = {
  groupList: document.getElementById('groupList'),
  groupSearch: document.getElementById('groupSearch'),
  btnNewGroup: document.getElementById('btnNewGroup'),
  btnEditGroup: document.getElementById('btnEditGroup'),
  btnDeleteGroup: document.getElementById('btnDeleteGroup'),
  currentGroupTitle: document.getElementById('currentGroupTitle'),
  serviceSearch: document.getElementById('serviceSearch'),
  activeFilter: document.getElementById('activeFilter'),
  btnNewService: document.getElementById('btnNewService'),
  servicesTbody: document.getElementById('servicesTbody'),

  groupModal: document.getElementById('groupModal'),
  groupForm: document.getElementById('groupForm'),
  groupModalTitle: document.getElementById('groupModalTitle'),
  groupCancel: document.getElementById('groupCancel'),

  serviceModal: document.getElementById('serviceModal'),
  serviceForm: document.getElementById('serviceForm'),
  serviceModalTitle: document.getElementById('serviceModalTitle'),
  serviceCancel: document.getElementById('serviceCancel'),

  groupItemTpl: document.getElementById('groupItemTpl'),
  serviceRowTpl: document.getElementById('serviceRowTpl'),
};

// -- Helpers
const pause = (ms)=> new Promise(r=>setTimeout(r, ms));

async function safeFetch(url, opts={}){
  const res = await fetch(url, Object.assign({headers:{'Content-Type':'application/json'}}, opts));
  if(!res.ok){
    const text = await res.text().catch(()=>'');
    throw new Error(`HTTP ${res.status} ${res.statusText}: ${text}`);
  }
  const ct = res.headers.get('content-type') || '';
  if(ct.includes('application/json')) return res.json();
  return res.text();
}

function formatCurrency(num){
  const n = Number(num||0);
  return new Intl.NumberFormat('ru-RU', {style:'currency', currency:'BYN'}).format(n);
}

function byName(a,b){ return a.name.localeCompare(b.name, 'ru') }
function sortGroups(arr){ return [...arr].sort((a,b)=> (a.order??0)-(b.order??0) || byName(a,b)) }
function sortServices(arr){ return [...arr].sort((a,b)=> byName(a,b)) }

function renderGroups(){
  els.groupList.innerHTML = '';
  const groups = sortGroups(state.groups).filter(g=> {
    const q = (els.groupSearch.value||'').trim().toLowerCase();
    return !q || g.name.toLowerCase().includes(q);
  });

  if(groups.length===0){
    const empty = document.createElement('div');
    empty.className = 'muted';
    empty.style.padding = '8px 10px';
    empty.textContent = 'Группы не найдены';
    els.groupList.appendChild(empty);
    return;
  }

  for(const g of groups){
    const li = els.groupItemTpl.content.firstElementChild.cloneNode(true);
    li.dataset.id = g.id;
    li.querySelector('.name').textContent = g.name;
    const count = state.services.filter(s=> s.groupId===g.id).length;
    li.querySelector('.count').textContent = count;
    if(g.id===state.currentGroupId) li.classList.add('active');
    li.querySelector('.group-btn').addEventListener('click', ()=>{
      state.currentGroupId = g.id;
      updateCurrentGroupUI();
      renderGroups();
      loadServices(g.id);
    });
    els.groupList.appendChild(li);
  }
}

function applyServiceFilters(items){
  let list = [...items];
  const q = (els.serviceSearch.value||'').trim().toLowerCase();
  const mode = els.activeFilter.value;
  if(q){
    list = list.filter(s=> (s.name||'').toLowerCase().includes(q) || (s.description||'').toLowerCase().includes(q));
  }
  if(mode==='active') list = list.filter(s=> !!s.isActive);
  if(mode==='inactive') list = list.filter(s=> !s.isActive);
  return sortServices(list);
}

function renderServices(){
  els.servicesTbody.innerHTML = '';
  const groupId = state.currentGroupId;
  const items = state.services.filter(s=> s.groupId===groupId);
  const list = applyServiceFilters(items);

  if(list.length===0){
    const tr = document.createElement('tr');
    tr.className = 'empty-row';
    const td = document.createElement('td');
    td.colSpan = 6; td.className = 'muted center';
    td.textContent = 'Нет услуг по условиям фильтра.';
    tr.appendChild(td);
    els.servicesTbody.appendChild(tr);
    return;
  }

  for(const s of list){
    const tr = els.serviceRowTpl.content.firstElementChild.cloneNode(true);
    tr.dataset.id = s.id;
    tr.querySelector('.name').textContent = s.name || '—';
    tr.querySelector('.desc').textContent = s.description || '—';
    tr.querySelector('.price').textContent = formatCurrency(s.price||0);
    tr.querySelector('.duration').textContent = `${s.durationMin||0} мин`;
    tr.querySelector('.active').textContent = s.isActive ? 'Да' : 'Нет';

    tr.querySelector('.edit').addEventListener('click', ()=> openServiceModal('edit', s));
    tr.querySelector('.del').addEventListener('click', ()=> deleteService(s));
    els.servicesTbody.appendChild(tr);
  }
}

function updateCurrentGroupUI(){
  const g = state.groups.find(x=> x.id===state.currentGroupId);
  const has = !!g;
  els.currentGroupTitle.textContent = has ? g.name : 'Выберите группу';
  els.btnEditGroup.disabled = !has;
  els.btnDeleteGroup.disabled = !has;
  els.btnNewService.disabled = !has;
}

// -- Modals
let editingGroupId = null;
function openGroupModal(mode, group=null){
  editingGroupId = (mode==='edit' && group) ? group.id : null;
  els.groupModalTitle.textContent = editingGroupId ? 'Редактировать группу' : 'Новая группа';
  els.groupForm.name.value = group?.name || '';
  els.groupForm.order.value = group?.order ?? 0;
  els.groupModal.showModal();
}

let editingServiceId = null;
function openServiceModal(mode, svc=null){
  if(!state.currentGroupId){
    alert('Сначала выберите группу');
    return;
  }
  editingServiceId = (mode==='edit' && svc) ? svc.id : null;
  els.serviceModalTitle.textContent = editingServiceId ? 'Редактировать услугу' : 'Новая услуга';
  els.serviceForm.name.value = svc?.name || '';
  els.serviceForm.description.value = svc?.description || '';
  els.serviceForm.price.value = svc?.price ?? 0;
  els.serviceForm.durationMin.value = svc?.durationMin ?? 60;
  els.serviceForm.isActive.checked = svc?.isActive ?? true;
  els.serviceModal.showModal();
}

// -- CRUD calls
async function loadGroups(){
  try{
    const data = await safeFetch(API.groups);
    state.groups = (data.items || data) ?? [];
    renderGroups();
    updateCurrentGroupUI();
  }catch(e){
    console.error('loadGroups failed', e);
    state.groups = [];
    renderGroups();
  }
}

async function loadServices(groupId){
  try{
    const data = await safeFetch(`${API.services}?groupId=${encodeURIComponent(groupId)}`);
    state.services = (data.items || data) ?? [];
  }catch(e){
    console.error('loadServices failed', e);
    state.services = [];
  }
  renderServices();
}

async function createOrUpdateGroup(evt){
  evt?.preventDefault();
  const payload = {
    name: els.groupForm.name.value.trim(),
    order: Number(els.groupForm.order.value||0),
  };
  try{
    if(editingGroupId){
      await safeFetch(`${API.groups}/${editingGroupId}`, {method:'PUT', body: JSON.stringify(payload)});
    }else{
      const created = await safeFetch(API.groups, {method:'POST', body: JSON.stringify(payload)});
      const id = created.id || created?.item?.id;
      if(id) state.currentGroupId = id;
    }
    els.groupModal.close();
    await loadGroups();
    if(state.currentGroupId) await loadServices(state.currentGroupId);
  }catch(e){
    alert('Ошибка сохранения группы: '+ e.message);
  }
}

async function deleteCurrentGroup(){
  if(!state.currentGroupId) return;
  if(!confirm('Удалить группу вместе с услугами?')) return;
  try{
    await safeFetch(`${API.groups}/${state.currentGroupId}`, {method:'DELETE'});
    state.currentGroupId = null;
    await loadGroups();
    renderServices();
  }catch(e){
    alert('Ошибка удаления: '+e.message);
  }
}

async function createOrUpdateService(evt){
  evt?.preventDefault();
  if(!state.currentGroupId) return;

  const payload = {
    groupId: state.currentGroupId,
    name: els.serviceForm.name.value.trim(),
    description: els.serviceForm.description.value.trim(),
    price: Number(els.serviceForm.price.value||0),
    durationMin: Number(els.serviceForm.durationMin.value||60),
    isActive: !!els.serviceForm.isActive.checked,
  };
  try{
    if(editingServiceId){
      await safeFetch(`${API.services}/${editingServiceId}`, {method:'PUT', body: JSON.stringify(payload)});
    }else{
      await safeFetch(API.services, {method:'POST', body: JSON.stringify(payload)});
    }
    els.serviceModal.close();
    await loadServices(state.currentGroupId);
    await loadGroups(); // обновить счётчики
  }catch(e){
    alert('Ошибка сохранения услуги: '+ e.message);
  }
}

async function deleteService(svc){
  if(!confirm(`Удалить услугу «${svc.name}»?`)) return;
  try{
    await safeFetch(`${API.services}/${svc.id}`, {method:'DELETE'});
    await loadServices(state.currentGroupId);
    await loadGroups();
  }catch(e){
    alert('Ошибка удаления: '+ e.message);
  }
}

// -- Events
els.btnNewGroup.addEventListener('click', ()=> openGroupModal('new'));
els.btnEditGroup.addEventListener('click', ()=> {
  const g = state.groups.find(x=> x.id===state.currentGroupId);
  if(g) openGroupModal('edit', g);
});
els.btnDeleteGroup.addEventListener('click', deleteCurrentGroup);
els.groupCancel.addEventListener('click', ()=> els.groupModal.close());
els.groupForm.addEventListener('submit', createOrUpdateGroup);
els.groupSearch.addEventListener('input', renderGroups);

els.btnNewService.addEventListener('click', ()=> openServiceModal('new'));
els.serviceCancel.addEventListener('click', ()=> els.serviceModal.close());
els.serviceForm.addEventListener('submit', createOrUpdateService);
els.serviceSearch.addEventListener('input', renderServices);
els.activeFilter.addEventListener('change', renderServices);

// -- Boot
(async function init(){
  await loadGroups();
  if(state.groups.length && !state.currentGroupId){
    state.currentGroupId = state.groups[0].id;
    updateCurrentGroupUI();
    await loadServices(state.currentGroupId);
  }
})();
