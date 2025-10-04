import React, { useEffect, useMemo, useState } from 'react';
import { api } from '../api';
import { CalendarMonth } from '../components/CalendarMonth';
import { DaySlots } from '../components/DaySlots';
import { Header } from '../components/Header';

export const ClientFlow: React.FC = () => {
  const [services, setServices] = useState<any[]>([]);
  const [masters, setMasters] = useState<any[]>([]);
  const [service, setService] = useState<any>(null);
  const [master, setMaster] = useState<any>(null);
  const [month, setMonth] = useState(() => {
    const d = new Date();
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}`;
  });
  const [available, setAvailable] = useState<number[]>([]);
  const [pickedDay, setPickedDay] = useState<number|undefined>();
  const [slots, setSlots] = useState<string[]>([]);
  const [me, setMe] = useState<any>(null);
  const tg = (window as any).Telegram?.WebApp;

  useEffect(() => {
    api.services().then(setServices);
    api.me().then(setMe).catch(()=>{});
  }, []);

  useEffect(() => {
    if (service) api.masters(service.id).then(setMasters);
  }, [service]);

  useEffect(() => {
    if (master) api.availability(master.id, month).then(r => setAvailable(r.available_days));
    setPickedDay(undefined);
    setSlots([]);
  }, [master, month]);

  useEffect(() => {
    if (pickedDay && master && service) {
      const date = `${month}-${String(pickedDay).padStart(2,'0')}`;
      api.slots(master.id, service.id, date).then(r => setSlots(r.slots));
    }
  }, [pickedDay, master, service, month]);

  const availSet = useMemo(() => new Set(available), [available]);

  const confirm = async (iso: string) => {
    const payload = {
      client_id: me?.id,
      master_id: master.id,
      service_id: service.id,
      start_at: iso
    };
    await api.createAppointment(payload);
    if (tg) {
      tg.showAlert('Запись создана!');
      tg.close();
    } else {
      alert('Запись создана!');
    }
  };

  return (
    <div className="container">
      <Header title="Онлайн запись" />
      <div className="card">
        <div className="row">
          <div style={{flex:1}}>
            <div style={{opacity:.7, fontSize:12}}>Клиент</div>
            <div>{me ? (me.first_name || me.username || 'Вы') : '...'}</div>
          </div>
        </div>
      </div>

      <div className="card">
        <div style={{opacity:.7, fontSize:12, marginBottom:6}}>Выберите услугу</div>
        <div className="grid" style={{gridTemplateColumns:'repeat(2, 1fr)'}}>
          {services.map(s => (
            <button key={s.id} className="btn" onClick={()=>setService(s)} style={{borderColor: service?.id===s.id ? '#29a36a' : undefined}}>
              <div>{s.name}</div>
              <div style={{opacity:.7, fontSize:12}}>{(s.price_minor/100).toFixed(2)} ₽ · {s.duration_min} мин</div>
            </button>
          ))}
        </div>
      </div>

      {service && (
        <div className="card">
          <div style={{opacity:.7, fontSize:12, marginBottom:6}}>Выберите мастера</div>
          <div className="grid" style={{gridTemplateColumns:'repeat(2, 1fr)'}}>
            {masters.map(m => (
              <button key={m.id} className="btn" onClick={()=>setMaster(m)} style={{borderColor: master?.id===m.id ? '#29a36a' : undefined}}>
                <div>{m.name}</div>
              </button>
            ))}
          </div>
        </div>
      )}

      {master && (
        <div className="card">
          <div className="row" style={{justifyContent:'space-between', marginBottom:8}}>
            <button className="btn" onClick={()=>{
              const d = new Date(month+'-01T00:00:00Z'); d.setUTCMonth(d.getUTCMonth()-1);
              setMonth(`${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}`);
            }}>←</button>
            <div style={{opacity:.8}}>{month}</div>
            <button className="btn" onClick={()=>{
              const d = new Date(month+'-01T00:00:00Z'); d.setUTCMonth(d.getUTCMonth()+1);
              setMonth(`${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}`);
            }}>→</button>
          </div>
          <CalendarMonth
            year={Number(month.slice(0,4))}
            monthIndex={Number(month.slice(5,7))-1}
            availableDays={availSet}
            onSelectDay={setPickedDay}
          />
        </div>
      )}

      {pickedDay && (
        <div className="card">
          <div style={{opacity:.7, fontSize:12, marginBottom:6}}>Выберите время</div>
          <DaySlots slots={slots} onPick={confirm} />
        </div>
      )}
    </div>
  );
};
