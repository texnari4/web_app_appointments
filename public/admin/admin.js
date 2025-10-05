async function jsonGET(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`GET ${url}`);
  return r.json();
}
async function jsonPOST(url, body) {
  const r = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  if (!r.ok) throw new Error(`POST ${url}`);
  return r.json();
}
async function jsonPUT(url, body) {
  const r = await fetch(url, { method:'PUT', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  if (!r.ok) throw new Error(`PUT ${url}`);
  return r.json();
}
async function jsonDELETE(url) {
  const r = await fetch(url, { method:'DELETE'});
  if (!r.ok) throw new Error(`DELETE ${url}`);
  return r.json();
}

const content = document.getElementById('content');
document.querySelectorAll('nav button').forEach(btn => {
  btn.addEventListener('click', () => loadTab(btn.dataset.tab));
});
loadTab('services');

async function loadTab(tab) {
  if (tab === 'services') {
    content.innerHTML = document.getElementById('tpl-services').innerHTML;
    await renderServices();
  } else if (tab === 'masters') {
    content.innerHTML = document.getElementById('tpl-masters').innerHTML;
    await renderMasters();
  }
}

async function renderMasters() {
  const list = document.getElementById('masters');
  const data = await jsonGET('/public/api/masters');
  list.innerHTML = '';
  for (const m of data.items) {
    const li = document.createElement('li');
    li.className = 'item';
    li.innerHTML = `<div class="cols"><strong>${m.name}</strong><span class="muted">${m.phone ?? ''}</span></div>
                    <div class="cols">
                      <button class="primary" data-id="${m.id}" data-act="del">Удалить</button>
                    </div>`;
    list.appendChild(li);
  }
  document.getElementById('addMasterBtn').onclick = async () => {
    const name = (document.getElementById('mName') as HTMLInputElement).value.trim();
    const phone = (document.getElementById('mPhone') as HTMLInputElement).value.trim();
    const avatarUrl = (document.getElementById('mAvatar') as HTMLInputElement).value.trim();
    await jsonPOST('/public/api/masters', { name, phone, avatarUrl, isActive: true });
    await renderMasters();
  };
  list.onclick = async (e) => {
    const t = e.target as HTMLElement;
    if (t.matches('button[data-act="del"]')) {
      const id = t.getAttribute('data-id');
      await jsonDELETE(`/public/api/masters/${id}`);
      await renderMasters();
    }
  };
}

async function renderServices() {
  const groupsEl = document.getElementById('groups');
  const servicesEl = document.getElementById('services');
  const selGroup = document.getElementById('svcGroup') as HTMLSelectElement;

  const groups = (await jsonGET('/public/api/service-groups')).items;
  const services = (await jsonGET('/public/api/services')).items;

  // groups UI
  groupsEl.innerHTML = '';
  selGroup.innerHTML = '';
  for (const g of groups) {
    const li = document.createElement('li');
    li.className = 'item';
    li.innerHTML = `<div class="cols"><strong>${g.name}</strong><span class="muted">${g.description ?? ''}</span></div>
                    <div class="cols"><button class="primary" data-id="${g.id}" data-act="del-group">Удалить</button></div>`;
    groupsEl.appendChild(li);

    const opt = document.createElement('option');
    opt.value = g.id;
    opt.textContent = g.name;
    selGroup.appendChild(opt);
  }

  // services UI
  servicesEl.innerHTML = '';
  for (const s of services) {
    const group = groups.find((g:any) => g.id === s.groupId);
    const li = document.createElement('li');
    li.className = 'item';
    li.innerHTML = `<div class="cols"><strong>${s.name}</strong><span class="muted">${group?.name ?? ''}</span>
                    <span class="muted">${s.durationMin} мин</span><span class="muted">${s.price} BYN</span></div>
                    <div class="cols"><button class="primary" data-id="${s.id}" data-act="del-service">Удалить</button></div>`;
    servicesEl.appendChild(li);
  }

  // handlers
  document.getElementById('addGroupBtn')!.onclick = async () => {
    const name = (document.getElementById('groupName') as HTMLInputElement).value.trim();
    const description = (document.getElementById('groupDesc') as HTMLInputElement).value.trim();
    await jsonPOST('/public/api/service-groups', { name, description });
    await renderServices();
  };
  document.getElementById('addServiceBtn')!.onclick = async () => {
    const groupId = selGroup.value;
    const name = (document.getElementById('svcName') as HTMLInputElement).value.trim();
    const description = (document.getElementById('svcDesc') as HTMLInputElement).value.trim();
    const price = Number((document.getElementById('svcPrice') as HTMLInputElement).value);
    const durationMin = Number((document.getElementById('svcDur') as HTMLInputElement).value);
    await jsonPOST('/public/api/services', { groupId, name, description, price, durationMin });
    await renderServices();
  };

  groupsEl.onclick = async (e) => {
    const t = e.target as HTMLElement;
    if (t.matches('button[data-act="del-group"]')) {
      const id = t.getAttribute('data-id');
      await jsonDELETE(`/public/api/service-groups/${id}`);
      await renderServices();
    }
  };
  servicesEl.onclick = async (e) => {
    const t = e.target as HTMLElement;
    if (t.matches('button[data-act="del-service"]')) {
      const id = t.getAttribute('data-id');
      await jsonDELETE(`/public/api/services/${id}`);
      await renderServices();
    }
  };
}
