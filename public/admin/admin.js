const API = '/public/api/masters';
const listEl = document.getElementById('list');
const msgEl = document.getElementById('msg');
const formEl = document.getElementById('createForm');
const saveBtn = document.getElementById('saveBtn');

function setMsg(text, kind='') {
  msgEl.className = kind;
  msgEl.textContent = text || '';
}

async function fetchJSON(input, init) {
  const res = await fetch(input, init);
  const ct = res.headers.get('content-type') || '';
  const data = ct.includes('application/json') ? await res.json() : null;
  if (!res.ok) {
    const errText = data?.error || res.statusText || 'Ошибка запроса';
    throw new Error(errText);
  }
  return data;
}

async function loadList() {
  try {
    const data = await fetchJSON(API);
    const items = data.items || [];
    listEl.innerHTML = '';
    if (!items.length) {
      listEl.innerHTML = '<p>Пока пусто.</p>';
      return;
    }
    for (const m of items) {
      const row = document.createElement('div');
      row.className = 'row';
      row.innerHTML = `
        <div class="meta">
          <img class="avatar" src="${m.avatarUrl || ''}" alt="" onerror="this.style.display='none'">
          <div>
            <div><strong>${m.name}</strong> <span class="status">(${m.phone})</span></div>
            <div class="status">${new Date(m.createdAt).toLocaleString()}</div>
          </div>
        </div>
      `;
      listEl.appendChild(row);
    }
  } catch (e) {
    setMsg('Ошибка загрузки списка: ' + (e.message || e), 'error');
  }
}

formEl.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  setMsg('');
  saveBtn.disabled = true;
  try {
    const fd = new FormData(formEl);
    const payload = {
      name: String(fd.get('name') || '').trim(),
      phone: String(fd.get('phone') || '').trim(),
      avatarUrl: String(fd.get('avatarUrl') || '').trim()
    };
    const res = await fetchJSON(API, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload)
    });
    setMsg('Сохранено', 'success');
    formEl.reset();
    await loadList();
  } catch (e) {
    setMsg('Ошибка сохранения: ' + (e.message || e), 'error');
  } finally {
    saveBtn.disabled = false;
  }
});

loadList();