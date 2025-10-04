import React from 'react';

type Props = {
  year: number;
  monthIndex: number; // 0-11
  availableDays: Set<number>;
  onSelectDay: (day: number) => void;
};

export const CalendarMonth: React.FC<Props> = ({ year, monthIndex, availableDays, onSelectDay }) => {
  const first = new Date(Date.UTC(year, monthIndex, 1));
  const startWeekday = (first.getUTCDay() + 6) % 7; // Monday=0
  const daysInMonth = new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
  const cells: Array<{ day?: number; disabled?: boolean }> = [];
  for (let i = 0; i < startWeekday; i++) cells.push({});
  for (let d = 1; d <= daysInMonth; d++) cells.push({ day: d, disabled: !availableDays.has(d) });

  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 8 }}>
      {['Пн','Вт','Ср','Чт','Пт','Сб','Вс'].map(w => (
        <div key={w} style={{ fontSize: 12, opacity: 0.7 }}>{w}</div>
      ))}
      {cells.map((c, i) => (
        <button
          key={i}
          disabled={!c.day || c.disabled}
          onClick={() => c.day && onSelectDay(c.day)}
          style={{
            aspectRatio: '1 / 1',
            borderRadius: 10,
            border: '1px solid #2a2a2a',
            background: c.day ? (c.disabled ? '#2a2a2a' : '#1a4c27') : 'transparent',
            color: c.day ? (c.disabled ? '#888' : '#fff') : 'transparent',
            cursor: c.day && !c.disabled ? 'pointer' : 'default'
          }}
        >
          {c.day ?? ''}
        </button>
      ))}
    </div>
  );
};
