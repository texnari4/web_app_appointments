import React from 'react';
export const Toast: React.FC<{ text: string }> = ({ text }) => (
  <div style={{ position:'fixed', bottom:16, left:16, right:16, background:'#1f2937', border:'1px solid #374151', borderRadius:10, padding:12, textAlign:'center' }}>
    {text}
  </div>
);
