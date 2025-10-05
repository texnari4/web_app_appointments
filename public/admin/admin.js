async function api(path, opts={}){
  const res = await fetch(path, {
    headers: { "Content-Type":"application/json" },
    ...opts
  });
  const data = await res.json().catch(()=>({ok:false,error:'BAD_JSON'}));
  if(!res.ok) throw new Error(data?.error || 'HTTP_'+res.status);
  return data;
}

async function loadList(){
  const el = document.getElementById('list');
  el.innerHTML = '<div class="muted">Загрузка...</div>';
  try {
    const { data } = await api('/api/masters');
    if(!data.length){
      el.innerHTML = '<div class="muted">Пока пусто</div>';
      return;
    }
    el.innerHTML = '';
    for(const m of data){
      const item = document.createElement('div');
      item.className = 'item';
      const img = document.createElement('img');
      img.className = 'avatar';
      img.src = m.photoUrl || 'https://dummyimage.com/88x88/f0f0f0/aaa.png&text=%F0%9F%91%A4';
      img.alt = m.name;
      const meta = document.createElement('div');
      meta.className = 'meta';
      const name = document.createElement('div');
      name.className = 'name';
      name.textContent = m.name;
      const sub = document.createElement('div');
      sub.className = 'muted';
      sub.textContent = [m.phone, m.specialty].filter(Boolean).join(' • ');
      meta.appendChild(name); meta.appendChild(sub);
      item.appendChild(img); item.appendChild(meta);
      el.appendChild(item);
    }
  } catch (e){
    el.innerHTML = '<div class="muted">Ошибка загрузки списка</div>';
  }
}

document.getElementById('reload').addEventListener('click', loadList);

const form = document.getElementById('form');
const msg = document.getElementById('msg');
form.addEventListener('submit', async (ev)=>{
  ev.preventDefault();
  msg.hidden = true;
  const fd = new FormData(form);
  const payload = Object.fromEntries(fd.entries());
  try {
    await api('/api/masters', { method:'POST', body: JSON.stringify(payload) });
    form.reset();
    msg.hidden = false; msg.style.color = '#2f855a'; msg.textContent = 'Сохранено ✓';
    await loadList();
  } catch(e){
    msg.hidden = false; msg.style.color = '#c53030'; msg.textContent = 'Ошибка сохранения';
  }
});

loadList();
