import React, { useMemo, useState } from 'react';
import { ClientFlow } from './pages/ClientFlow';
import { MasterJournal } from './pages/MasterJournal';
import { MasterClients } from './pages/MasterClients';
import { MasterSchedule } from './pages/MasterSchedule';
import { MasterNotifications } from './pages/MasterNotifications';
import { MasterProfile } from './pages/MasterProfile';
import { AdminPanel } from './pages/AdminPanel';

export const App: React.FC = () => {
  const tg = (window as any).Telegram?.WebApp;
  const initUser = useMemo(()=> {
    try { return tg?.initDataUnsafe?.user || null } catch { return null }
  }, [tg]);
  const [tab, setTab] = useState<'client'|'journal'|'clients'|'schedule'|'notifications'|'profile'|'admin'>('client');

  return (
    <div>
      <nav className="card" style={{position:'sticky', top:0, display:'grid', gridTemplateColumns:'repeat(7,1fr)', gap:6}}>
        <button className="btn" onClick={()=>setTab('client')}>Клиент</button>
        <button className="btn" onClick={()=>setTab('journal')}>Журнал</button>
        <button className="btn" onClick={()=>setTab('clients')}>Клиенты</button>
        <button className="btn" onClick={()=>setTab('schedule')}>График</button>
        <button className="btn" onClick={()=>setTab('notifications')}>Уведомления</button>
        <button className="btn" onClick={()=>setTab('profile')}>Ещё</button>
        <button className="btn" onClick={()=>setTab('admin')}>Админ</button>
      </nav>
      {tab==='client' && <ClientFlow />}
      {tab==='journal' && <MasterJournal />}
      {tab==='clients' && <MasterClients />}
      {tab==='schedule' && <MasterSchedule />}
      {tab==='notifications' && <MasterNotifications />}
      {tab==='profile' && <MasterProfile />}
      {tab==='admin' && <AdminPanel />}
    </div>
  );
};
