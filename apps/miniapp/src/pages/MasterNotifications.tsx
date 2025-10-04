import React from 'react';
import { Header } from '../components/Header';

export const MasterNotifications: React.FC = () => {
  return (
    <div className="container">
      <Header title="Уведомления" />
      <div className="card">Здесь будут уведомления о новых/отменённых записях.</div>
    </div>
  );
};
