/**
 * Sends the family notices the operator console queues
 * (docs/management-platform-plan.md §2.3). The console's database role cannot
 * see who is in a family, so it writes admin_family_notices; the public backend,
 * which can, picks them up here and pushes to the family's caregivers.
 *
 * Each notice is claimed (sent_at set) before it is sent, so two backends never
 * send the same one. A push that fails after the claim is not retried: these
 * are nudges, and the audit log still records the request.
 */
import { notifyFamilyCaregivers } from '../utils/notify.js';

export const NOTICE_MESSAGES = {
  inactive: {
    title: 'Is your family still using CareCoins?',
    body: 'Your family has been quiet for a while. Open the app to keep it active.',
    url: '/dashboard',
    prefKey: 'family_events',
  },
};

export async function deliverPendingNotices(db, notify = notifyFamilyCaregivers, batchSize = 20) {
  const { rows } = await db.query(
    `UPDATE admin_family_notices SET sent_at = NOW()
     WHERE id IN (
       SELECT id FROM admin_family_notices
       WHERE sent_at IS NULL
       ORDER BY id
       LIMIT $1
       FOR UPDATE SKIP LOCKED
     )
     RETURNING id, family_id, kind`,
    [batchSize]
  );

  let sent = 0;
  for (const row of rows) {
    const message = NOTICE_MESSAGES[row.kind];
    if (!message) continue;
    await notify(Number(row.family_id), 0, message);
    sent++;
  }
  return sent;
}

export function startNoticeOutbox(db, { intervalMs = 60_000 } = {}) {
  const tick = () => deliverPendingNotices(db).catch((err) => {
    console.error('Notice outbox failed:', err);
  });
  const timer = setInterval(tick, intervalMs);
  timer.unref();
  return timer;
}
