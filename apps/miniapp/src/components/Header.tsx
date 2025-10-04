import React from 'react';
export const Header: React.FC<{ title: string, subtitle?: string }> = ({ title, subtitle }) => (
  <div style={{ padding: '12px 0' }}>
    <h2 style={{ margin: 0 }}>{title}</h2>
    {subtitle && <div style={{ opacity: .7 }}>{subtitle}</div>}
  </div>
);
