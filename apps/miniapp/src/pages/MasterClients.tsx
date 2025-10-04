import React, { useEffect, useMemo, useState } from 'react';
import { Header } from '../components/Header';

export const MasterClients: React.FC = () => {
  const [q, setQ] = useState('');
  const [rows, setRows] = useState<any[]>([]);
  useEffect(()=>{ fetch(); },[]);
  async function fetch(){
    const res = await fetch('/api/master/clients', { headers: { 'x-telegram-init-data': (window as any).Telegram?.WebApp?.initData || '' } });
    if (res.ok) setRows(await res.json());
  }
  const filtered = useMemo(()=> rows.filter((c:any)=> (c.first_name+' '+(c.last_name||'')+' '+(c.phone||'')).toLowerCase().includes(q.toLowerCase())),[rows,q]);
  return (
    <div className="container">
      <Header title="Клиенты" />
      <input className="btn" placeholder="Поиск по имени/телефону" value={q} onChange={e=>setQ(e.target.value)} />
      {filtered.map(c => (
        <div key={c.id} className="card">
          <div><b>{c.first_name} {c.last_name || ''}</b></div>
          <div className="row" style={{gap:6, marginTop:6}}>
            {c.phone && <a className="btn" href={`tel:${c.phone}`}>Позвонить</a>}
            {c.username && <a className="btn" href={`https://t.me/${c.username}`} target="_blank">Написать</a>}
          </div>
        </div>
      ))}
    </div>
  );
};
