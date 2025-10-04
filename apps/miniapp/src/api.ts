const base = '';

function initData() {
  const tg = (window as any).Telegram?.WebApp;
  return tg?.initData || '';
}

async function getJSON<T>(path: string) {
  const res = await fetch(`${base}/api${path}`, { headers: { 'x-telegram-init-data': initData() } });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<T>;
}

async function postJSON<T>(path: string, body: any) {
  const res = await fetch(`${base}/api${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-telegram-init-data': initData() },
    body: JSON.stringify(body)
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<T>;
}

export const api = {
  services: () => getJSON<any[]>('/services'),
  masters: (service_id?: string) => getJSON<any[]>(`/masters${service_id ? `?service_id=${service_id}` : ''}`),
  availability: (master_id: string, month: string) => getJSON<{month:string, available_days:number[]}>(`/availability?master_id=${master_id}&month=${month}`),
  slots: (master_id: string, service_id: string, date: string) => getJSON<{slots:string[], step_min:number, duration_min:number}>(`/slots?master_id=${master_id}&service_id=${service_id}&date=${date}`),
  createAppointment: (payload: any) => postJSON<{id:string}>('/appointments', payload),
  me: () => getJSON('/client/me'),
  masterDay: (date: string) => getJSON(`/master/day-schedule?date=${date}`),
  adminAppointments: () => getJSON('/admin/appointments')
};
