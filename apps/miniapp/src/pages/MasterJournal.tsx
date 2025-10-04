import React, { useEffect, useState } from 'react';
import { api } from '../api';
import { Header } from '../components/Header';

export const MasterJournal: React.FC = () => {
  const [date, setDate] = useState(() => new Date().toISOString().slice(0,10));
  const [rows, setRows] = useState<any[]>([]);
  useEffect(() => { api.masterDay(date).then(setRows); }, [date]);
  return (
    <div className="container">
      <Header title="Журнал" subtitle={date} />
      <div className="row" style={{gap:6}}>
        <input value={date} type="date" onChange={e=>setDate(e.target.value)} />
      </div>
      {rows.map(r => (
        <div key={r.id} className="card">
          <div><b>{r.service}</b> — {new Date(r.start_at).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'})}–{new Date(r.end_at).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'})}</div>
          <div style={{opacity:.7}}>{r.first_name} {r.last_name || ''} · {r.status}</div>
          <div className="row" style={{gap:6, marginTop:6}}>
            {r.phone && <a className="btn" href={`tel:${r.phone}`}>Позвонить</a>}
            {r.username && <a className="btn" href={`https://t.me/${r.username}`} target="_blank">Написать</a>}
          </div>
        </div>
      ))}
    </div>
  );
};
