import React from 'react';
type Props = { slots: string[]; onPick: (iso: string) => void };
export const DaySlots: React.FC<Props> = ({ slots, onPick }) => {
  if (!slots.length) return <div style={{opacity:.7}}>Нет свободных слотов</div>;
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
      {slots.map(s => (
        <button key={s} className="btn" onClick={() => onPick(s)}>{new Date(s).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'})}</button>
      ))}
    </div>
  );
};
