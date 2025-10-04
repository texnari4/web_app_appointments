import React, { useEffect, useState } from 'react';
import { Header } from '../components/Header';

export const AdminPanel: React.FC = () => {
  const [apps, setApps] = useState<any[]>([]);
  useEffect(()=>{ fetch(); },[]);
  async function fetch(){
    const res = await fetch('/api/admin/appointments', { headers: { 'x-telegram-init-data': (window as any).Telegram?.WebApp?.initData || '' } });
    if (res.ok) setApps(await res.json());
  }
  return (
    <div className="container">
      <Header title="Админ‑панель" />
      <div className="card">
        <b>Записи</b>
        {apps.map(a => (
          <div key={a.id} className="row" style={{justifyContent:'space-between'}}>
            <div>{new Date(a.start_at).toLocaleString()}</div>
            <div>{a.service} — {a.master}</div>
            <div>{(a.price_minor/100).toFixed(2)} ₽</div>
          </div>
        ))}
      </div>
    </div>
  );
};
