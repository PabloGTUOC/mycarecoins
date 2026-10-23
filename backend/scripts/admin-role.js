/**
 * The carecoins_admin role (docs/management-platform-plan.md §2.3).
 *
 * The operator console's API connects as this role. It can read the views and
 * billing tables listed below and nothing else: no members, activities, coins,
 * rewards or users. Every run first revokes everything, then grants the list
 * again, so a grant removed here disappears from production on the next start.
 *
 * Without ADMIN_DB_PASSWORD (local dev, CI) the role is not created; if it
 * already exists its grants are still refreshed.
 */

export const ADMIN_ROLE = 'carecoins_admin';

// Content tables the role must never read. tests/adminConsole.test.js and the
// E2E check (scripts/check-admin-role.js) use this list; add new content
// tables here.
export const FORBIDDEN_TABLES = [
  'users', 'families', 'family_members', 'actors', 'activities', 'coin_ledger',
  'marketplace_rewards', 'reward_redemptions', 'absences', 'personal_time_requests',
  'family_invitations', 'invite_links', 'fcm_tokens', 'notification_preferences',
  'login_history', 'onboarding_events', 'family_deletion_requests',
  'family_deletion_approvals', 'device_keys',
];

export const GRANT_STATEMENTS = [
  `GRANT USAGE ON SCHEMA public TO ${ADMIN_ROLE}`,
  `GRANT SELECT ON admin_family_registry, admin_operators, plans, family_plans,
     admin_grants, admin_audit_log, admin_rc_sync, admin_family_notices TO ${ADMIN_ROLE}`,
  // Webhook metadata only: the raw payload can carry a customer's attributes.
  `GRANT SELECT (id, provider, event_id, event_type, family_id, processed, created_at)
     ON billing_events TO ${ADMIN_ROLE}`,
  `GRANT INSERT, UPDATE ON plans TO ${ADMIN_ROLE}`,
  `GRANT INSERT, UPDATE (revoked_at) ON admin_grants TO ${ADMIN_ROLE}`,
  `GRANT INSERT ON admin_audit_log TO ${ADMIN_ROLE}`,
  `GRANT INSERT, UPDATE ON admin_rc_sync TO ${ADMIN_ROLE}`,
  `GRANT INSERT ON admin_family_notices TO ${ADMIN_ROLE}`,
  `GRANT USAGE ON SEQUENCE admin_grants_id_seq, admin_audit_log_id_seq,
     admin_family_notices_id_seq TO ${ADMIN_ROLE}`,
];

export async function applyAdminRole(pool, password = process.env.ADMIN_DB_PASSWORD) {
  const client = await pool.connect();
  try {
    if (password) {
      const { rows } = await client.query(`SELECT 1 FROM pg_roles WHERE rolname = $1`, [ADMIN_ROLE]);
      if (!rows.length) await client.query(`CREATE ROLE ${ADMIN_ROLE} LOGIN`);
      await client.query(
        `ALTER ROLE ${ADMIN_ROLE} WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD ${client.escapeLiteral(password)}`
      );
    } else {
      const { rows } = await client.query(`SELECT 1 FROM pg_roles WHERE rolname = $1`, [ADMIN_ROLE]);
      if (!rows.length) return { created: false, granted: false };
    }

    await client.query('BEGIN');
    await client.query(`REVOKE ALL ON ALL TABLES IN SCHEMA public FROM ${ADMIN_ROLE}`);
    await client.query(`REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM ${ADMIN_ROLE}`);
    await client.query(`REVOKE CREATE ON SCHEMA public FROM ${ADMIN_ROLE}`);
    for (const sql of GRANT_STATEMENTS) await client.query(sql);
    await client.query('COMMIT');
    return { created: Boolean(password), granted: true };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}
