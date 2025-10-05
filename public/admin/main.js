
async function load() {
  const r = await fetch('/public/api/masters');
  const j = await r.json();
  const ul = document.querySelector('#list');
  ul.innerHTML = '';
  (j.items || []).forEach(m => {
    const li = document.createElement('li');
    li.innerHTML = `<img src="${m.avatarUrl || ''}" onerror="this.style.display='none'"/> <b>${m.name}</b> <span>${m.phone}</span>`;
    ul.appendChild(li);
  });
}
document.querySelector('#f').addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const payload = Object.fromEntries(fd.entries());
  const r = await fetch('/public/api/masters', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify(payload)
  });
  if (r.ok) {
    e.target.reset();
    await load();
  } else {
    alert('Ошибка сохранения');
  }
});
load();
