/**
 * Free-plan RevenueCat synchronization worker.
 *
 * Docs reference: https://www.revenuecat.com/docs/api-v2/customer
 * Plan reference: docs/management-platform-plan.md §4 and §7 Phase 3.
 */
import { RevenueCatError } from './revenuecat.js';

export async function syncPending(
  db,
  rc,
  { entitlementId, now = () => new Date(), batch = 20, grantId = null } = {}
) {
  if (!rc) throw new Error('RevenueCat client is required for syncPending');
  if (!entitlementId) throw new Error('entitlementId is required for syncPending');

  const nowDate = typeof now === 'function'
    ? new Date(now())
    : (now instanceof Date ? now : (now ? new Date(now) : new Date()));

  const maxRows = grantId != null ? 1 : Math.max(1, Number(batch) || 20);
  const results = [];

  for (let i = 0; i < maxRows; i++) {
    const client = typeof db.connect === 'function' ? await db.connect() : db;
    try {
      await client.query('BEGIN');

      let querySql;
      let queryParams;

      if (grantId != null) {
        querySql = `
          SELECT s.grant_id, s.rc_customer_id, s.action, s.status, s.attempts,
                 g.family_id, g.expires_at, g.revoked_at
          FROM admin_rc_sync s
          JOIN admin_grants g ON g.id = s.grant_id
          WHERE s.grant_id = $1
          FOR UPDATE OF s SKIP LOCKED
        `;
        queryParams = [grantId];
      } else {
        querySql = `
          SELECT s.grant_id, s.rc_customer_id, s.action, s.status, s.attempts,
                 g.family_id, g.expires_at, g.revoked_at
          FROM admin_rc_sync s
          JOIN admin_grants g ON g.id = s.grant_id
          WHERE s.status IN ('pending', 'failed')
            AND ((s.attempts = 0 AND s.updated_at <= $1)
                 OR (s.updated_at + (LEAST(POWER(2, s.attempts), 60) * INTERVAL '1 minute') <= $1))
          ORDER BY s.updated_at ASC
          LIMIT 1
          FOR UPDATE OF s SKIP LOCKED
        `;
        queryParams = [nowDate];
      }

      const { rows } = await client.query(querySql, queryParams);
      if (!rows.length) {
        await client.query('ROLLBACK');
        break;
      }

      const row = rows[0];

      try {
        if (row.action === 'grant') {
          const isExpired = row.expires_at && (new Date(row.expires_at).getTime() <= nowDate.getTime());
          if (!isExpired) {
            await rc.ensureCustomer(row.rc_customer_id, [
              { name: 'family_id', value: String(row.family_id) },
            ]);

            let expiresAtMs;
            if (row.expires_at) {
              expiresAtMs = new Date(row.expires_at).getTime();
            } else {
              // Lifetime: now + 100 years
              expiresAtMs = nowDate.getTime() + (100 * 365.25 * 24 * 60 * 60 * 1000);
            }

            await rc.grantEntitlement(row.rc_customer_id, entitlementId, expiresAtMs);
          }
        } else if (row.action === 'revoke') {
          try {
            await rc.revokeGrantedEntitlement(row.rc_customer_id, entitlementId);
          } catch (err) {
            if (err instanceof RevenueCatError && err.status === 404) {
              // 404 (no such customer or no granted entitlement) counts as synced.
            } else {
              throw err;
            }
          }

          // Revoke takes away every grant on the customer. If the family still has
          // another active grant, re-grant with the latest remaining expiry.
          const { rows: remainingRows } = await client.query(
            `SELECT id, expires_at
             FROM admin_grants
             WHERE family_id = $1
               AND id <> $2
               AND revoked_at IS NULL
               AND (expires_at IS NULL OR expires_at > $3)
             ORDER BY (expires_at IS NULL) DESC, expires_at DESC
             LIMIT 1`,
            [row.family_id, row.grant_id, nowDate]
          );

          if (remainingRows.length > 0) {
            const remaining = remainingRows[0];
            let remainingExpiresAtMs;
            if (remaining.expires_at) {
              remainingExpiresAtMs = new Date(remaining.expires_at).getTime();
            } else {
              // Lifetime: now + 100 years
              remainingExpiresAtMs = nowDate.getTime() + (100 * 365.25 * 24 * 60 * 60 * 1000);
            }
            await rc.grantEntitlement(row.rc_customer_id, entitlementId, remainingExpiresAtMs);
          }
        }

        await client.query(
          `UPDATE admin_rc_sync
           SET status = 'synced',
               synced_at = $1,
               attempts = 0,
               last_error = NULL,
               updated_at = NOW()
           WHERE grant_id = $2`,
          [nowDate, row.grant_id]
        );
        await client.query('COMMIT');
        results.push({ grantId: Number(row.grant_id), status: 'synced' });
      } catch (err) {
        const isUnavailable = err instanceof RevenueCatError ? err.kind === 'unavailable' : false;
        const newAttempts = Number(row.attempts || 0) + 1;

        if (isUnavailable) {
          await client.query(
            `UPDATE admin_rc_sync
             SET status = 'pending',
                 attempts = attempts + 1,
                 updated_at = NOW()
             WHERE grant_id = $1`,
            [row.grant_id]
          );
          await client.query('COMMIT');
          results.push({ grantId: Number(row.grant_id), status: 'pending', attempts: newAttempts });
        } else {
          // Rejected or other error -> failed
          const safeError = String(err?.message || 'RevenueCat error').slice(0, 500);

          await client.query(
            `UPDATE admin_rc_sync
             SET status = 'failed',
                 attempts = attempts + 1,
                 last_error = $1,
                 updated_at = NOW()
             WHERE grant_id = $2`,
            [safeError, row.grant_id]
          );
          await client.query('COMMIT');
          results.push({
            grantId: Number(row.grant_id),
            status: 'failed',
            attempts: newAttempts,
            lastError: safeError,
          });
        }
      }
    } catch (dbErr) {
      await client.query('ROLLBACK').catch(() => {});
      throw dbErr;
    } finally {
      if (typeof client.release === 'function') client.release();
    }
  }

  return { processed: results.length, results };
}
