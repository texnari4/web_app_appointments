const $ = (q,root=document)=>root.querySelector(q);
const $$ = (q,root=document)=>Array.from(root.querySelectorAll(q));

async function jsonGET(url){
  const r = await fetch(url);
  if(!r.ok) throw new Error(`GET ${url}`);
  return r.json();
}
async function jsonPOST(url, body){
  const r = await fetch(url, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  if(!r.ok) throw new Error(`POST ${url}`);
  return r.json();
}

function activateTab(name){
  $$('.tab').forEach(b=>b.classList.toggle('active', b.dataset.tab===name));
  $$('.panel').forEach(p=>p.classList.toggle('active', p.id===`tab-${name}`));
}

async function renderMasters(){
  const box = $('#masters-list');
  box.innerHTML = '<div class="item">Загрузка...</div>';
  const data = await jsonGET('/public/api/masters');
  box.innerHTML = '';
  for(const m of data.items){
    const el = document.createElement('div');
    el.className='item';
    el.innerHTML = `
      <div class="row">
        <img class="avatar" src="${m.avatarUrl||'https://placehold.co/96x96'}" alt="">
        <div>
          <h3>${m.name}</h3>
          <div class="muted">${m.phone||''}</div>
        </div>
      </div>`;
    box.appendChild(el);
  }
}

async function renderServices(){
  const box = $('#services-list');
  box.innerHTML = '<div class="item">Загрузка...</div>';
  try{
    const data = await jsonGET('/public/api/services');
    box.innerHTML = '';
    if(!data.items?.length){
      box.innerHTML = '<div class="item">Пока нет услуг</div>';
      return;
    }
    for(const s of data.items){
      const el = document.createElement('div');
      el.className='item';
      el.innerHTML = `
        <h3>${s.name}</h3>
        <div class="muted">${s.groupName||''}</div>
        <div>${s.description||''}</div>
        <div class="muted">${s.durationMinutes} мин · ${s.price} BYN</div>`;
      box.appendChild(el);
    }
  }catch(e){
    box.innerHTML = `<div class="item">Ошибка загрузки услуг</div>`;
  }
}

async function loadTab(name){
  activateTab(name);
  if(name==='masters') await renderMasters();
  if(name==='services') await renderServices();
}

async function init(){
  // tabs
  $$('.tab').forEach(b=>b.addEventListener('click',()=>loadTab(b.dataset.tab)));

  // create master
  $('#form-master').addEventListener('submit', async (e)=>{
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const body = Object.fromEntries(fd.entries());
    body.isActive = true;
    try{
      await jsonPOST('/public/api/masters', body);
      $('#status-master').textContent = 'Сохранено';
      await renderMasters();
      e.currentTarget.reset();
      setTimeout(()=>$('#status-master').textContent='', 1500);
    }catch(err){
      $('#status-master').textContent = 'Ошибка сохранения';
    }
  });

  await loadTab('masters');
}
init();
