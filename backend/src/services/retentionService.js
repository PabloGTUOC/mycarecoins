/**
 * Retention for abandoned families (docs/admin-family-management-plan.md
 * Phase 6).
 *
 * The privacy boundary means an admin never deletes family data directly;
 * they trigger a *process*: send an inactivity notice (Phase 2, audited),
 * wait, and then this sweep deletes families that stayed silent. Both steps
 * are visible in admin_audit_log.
 *
 * A family qualifies only when BOTH hold:
 *   - last_active_at is older than `inactiveDays` (default 365), and
 *   - the most recent 'family.notify_inactive' audit entry is older than
 *     `noticeDays` (default 30) — the family was warned and didn't return.
 *
 * Deletion re-verifies inactivity in its own WHERE clause so a family that
 * came back between listing and deletion is skipped, and it cascades via
 * the existing ON DELETE rules. The audit row is attributed to the admin
 * whose notice started the process.
 */
import { logAdminAction } from './adminService.js';
import { serviceError } from '../utils/httpError.js';

export async function findRetentionCandidates(client, { inactiveDays = 365, noticeDays = 30 } = {}) {
  const { rows } = await client.query(
    `SELECT f.id, f.name, f.last_active_at, n.admin_id AS noticed_by, n.created_at AS noticed_at
     FROM families f
     JOIN LATERAL (
       SELECT admin_id, created_at FROM admin_audit_log
        WHERE action = 'family.notify_inactive'
          AND target_type = 'family' AND target_id = f.id::text
        ORDER BY created_at DESC LIMIT 1
     ) n ON true
     WHERE f.last_active_at < NOW() - make_interval(days => $1)
       AND n.created_at < NOW() - make_interval(days => $2)
     ORDER BY f.last_active_at`,
    [inactiveDays, noticeDays]
  );
  return rows.map(r => ({
    id: Number(r.id),
    name: r.name,
    lastActiveAt: r.last_active_at,
    noticedBy: Number(r.noticed_by),
    noticedAt: r.noticed_at,
  }));
}

export async function deleteRetainedFamily(client, candidate, { inactiveDays = 365 } = {}) {
  const { rowCount } = await client.query(
    `DELETE FROM families
     WHERE id = $1 AND last_active_at < NOW() - make_interval(days => $2)`,
    [candidate.id, inactiveDays]
  );
  if (!rowCount) {
    return serviceError(409, 'retentionFamilyBecameActive', 'Family became active again — skipped.');
  }

  await logAdminAction(client, candidate.noticedBy, 'family.retention_delete', {
    targetType: 'family',
    targetId: candidate.id,
    payload: {
      name: candidate.name,
      lastActiveAt: candidate.lastActiveAt,
      noticedAt: candidate.noticedAt,
    },
  });
  return { data: { deleted: true } };
}
