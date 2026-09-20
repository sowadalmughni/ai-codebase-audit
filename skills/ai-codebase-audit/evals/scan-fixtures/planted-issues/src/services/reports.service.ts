import { db } from '../db';

// Fixture: classic N+1 — one query per iteration inside a for loop.
export async function attachOrderTotals(userIds: string[]) {
  const results = [];
  for (const userId of userIds) {
    const orders = await db.query('SELECT * FROM orders WHERE user_id = $1', [userId]);
    results.push(orders);
  }
  return results;
}
