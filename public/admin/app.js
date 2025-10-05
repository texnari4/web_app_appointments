
const apiBase = '/public/api/masters';

const listEl = document.getElementById('list');
const tpl = document.getElementById('item-tpl');
const form = document.getElementById('create-form');
const formStatus = document.getElementById('form-status');
const refreshBtn = document.getElementById('refresh');

function el(q, ctx=document){ return ctx.querySelector(q); }
function text(node, s){ node.textContent = s; }

async function fetchJSON(url, opts) {
  const r = await fetch(url, { headers: { 'Content-Type':'application/json' }, ...opts });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return await r.json();
}

function renderItem(m) {
  const node = tpl.content.firstElementChild.cloneNode(true);
  el('.title', node).textContent = m.name;
  el('.subtitle', node).textContent = `${m.phone} · ${m.isActive ? 'Активен' : 'Отключен'}`;
  const toggle = el('.toggle', node);
  toggle.checked = !!m.isActive;
  toggle.addEventListener('change', async () => {
    try{
      await fetchJSON(`${apiBase}/${m.id}/toggle`, {
        method: 'POST',
        body: JSON.stringify({ isActive: toggle.checked })
      });
      el('.subtitle', node).textContent = `${m.phone} · ${toggle.checked ? 'Активен' : 'Отключен'}`;
    }catch(e){
      toggle.checked = !toggle.checked;
      alert('Ошибка переключения статуса');
    }
  });
  return node;
}

async function loadList() {
  const data = await fetchJSON(apiBase);
  listEl.innerHTML = '';
  data.items.forEach(m => listEl.appendChild(renderItem(m)));
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(form);
  const payload = Object.fromEntries(fd.entries());
  if(!payload.name || !payload.phone){
    formStatus.textContent = 'Укажите имя и телефон';
    return;
  }
  try{
    formStatus.textContent = 'Сохраняю...';
    const { item } = await fetchJSON(apiBase, { method: 'POST', body: JSON.stringify({ 
      name: payload.name, phone: payload.phone, avatarUrl: payload.avatarUrl || '', isActive: true 
    })});
    // prepend new item without reload
    listEl.prepend(renderItem(item));
    form.reset();
    formStatus.textContent = 'Готово ✔';
    setTimeout(() => formStatus.textContent = '', 1500);
  }catch(err){
    formStatus.textContent = 'Ошибка сохранения';
  }
});

refreshBtn.addEventListener('click', loadList);
loadList();
