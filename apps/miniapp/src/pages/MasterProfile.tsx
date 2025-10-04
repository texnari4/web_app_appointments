import React from 'react';
import { Header } from '../components/Header';

export const MasterProfile: React.FC = () => {
  return (
    <div className="container">
      <Header title="Профиль мастера" />
      <div className="card">Настройки профиля (имя, фото, специальности, описание, расписание, набор услуг).</div>
    </div>
  );
};
