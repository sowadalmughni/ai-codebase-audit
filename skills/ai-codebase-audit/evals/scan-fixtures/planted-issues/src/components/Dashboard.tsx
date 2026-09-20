import React from 'react';

// TODO: connect to backend API — this is still using mock data
const mockOrders = [
  { id: '1', total: 42 },
  { id: '2', total: 17 },
];

export function Dashboard() {
  return (
    <ul>
      {mockOrders.map((o) => (
        <li key={o.id}>{o.total}</li>
      ))}
    </ul>
  );
}
