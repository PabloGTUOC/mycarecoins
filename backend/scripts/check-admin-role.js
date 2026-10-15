/**
 * Proves the carecoins_admin boundary against a real database
 * (docs/management-platform-plan.md §2.3). Run after `npm run db:init` with
 * ADMIN_DB_PASSWORD set:
 *
 *   DATABASE_URL=postgres://postgres:test@localhost:55432/cc \
 *   ADMIN_DATABASE_URL=postgres://carecoins_admin:<pw>@localhost:55432/cc \
 *   node scripts/check-admin-role.js
 *
 * It seeds one family as the owner role, then, as carecoins_admin: every
 * content table refuses a SELECT, the registry and billing reads work, and the
 * console's writes succeed. It cleans up after itself. Exits non-zero on any
 * failure. Never run it against production.
 */
import pg from 'pg';
import { FORBIDDEN_TABLES, ADMIN_ROLE } from './admin-role.js';
import * as adminService from '../src/services/adminService.js';

const owner = new pg.Client({ connectionString: process.env.DATABASE_URL });
const admin = new pg.Client({ connectionString: process.env.ADMIN_DATABASE_URL });

const failures = [];
const check = (ok, label) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}`); if (!ok) failures.push(label); };

async function refuses(sql, label) {
  try {
    await admin.query(sql);
    check(false, `${label} (it was allowed)`);
  } catch (err) {
    check(err.code === '42501', `${label} is refused`);
  }
}

async function main() {
  await owner.connect();
  await admin.connect();

  const { rows: [{ role }] } = await admin.query('SELECT current_user AS role');
  check(role === ADMIN_ROLE, `connected as ${ADMIN_ROLE}`);

  // Seed as the owner.
  await owner.query('BEGIN');
  const { rows: [u] } = await owner.query(
    `INSERT INTO users (firebase_uid, email, display_name, platform_role)
     VALUES ('check-admin-role', 'check-admin-role@example.invalid', 'Check', 'admin') RETURNING id`);
  const { rows: [f] } = await owner.query(
    `INSERT INTO families (name, created_by) VALUES ('Check family', $1) RETURNING id`, [u.id]);
  await owner.query(
    `INSERT INTO family_members (family_id, user_id, role, status) VALUES ($1, $2, 'caregiver', 'active')`,
    [f.id, u.id]);
  await owner.query('COMMIT');

  try {
    // Every table must be either granted to the console or listed as content,
    // so a new table cannot slip past this check unnoticed.
    const granted = ['plans', 'family_plans', 'billing_events', 'admin_grants', 'admin_audit_log',
      'admin_rc_sync', 'admin_family_notices'];
    const { rows: tables } = await owner.query(
      `SELECT table_name FROM information_schema.tables
       WHERE table_schema = 'public' AND table_type = 'BASE TABLE'`);
    const unclassified = tables.map((t) => t.table_name)
      .filter((t) => !granted.includes(t) && !FORBIDDEN_TABLES.includes(t));
    check(!unclassified.length, `every table is classified${unclassified.length ? ` (missing: ${unclassified.join(', ')})` : ''}`);

    for (const table of FORBIDDEN_TABLES) {
      await refuses(`SELECT 1 FROM ${table} LIMIT 1`, `SELECT on ${table}`);
    }
    await refuses('SELECT payload FROM billing_events LIMIT 1', 'SELECT billing_events.payload');
    await refuses(`UPDATE admin_grants SET plan_code = plan_code`, 'UPDATE admin_grants.plan_code');
    await refuses(`DELETE FROM admin_audit_log`, 'DELETE on admin_audit_log');
    await refuses(`CREATE TABLE admin_sneaky (id int)`, 'CREATE TABLE');

    const listed = await adminService.listFamilies(admin, { search: 'Check family' });
    const entry = listed.data.families.find((x) => x.id === Number(f.id));
    check(entry?.memberCount === 1, 'listFamilies works and counts members through the view');

    const detail = await adminService.getFamilyRegistry(admin, Number(f.id));
    check(detail.data?.name === 'Check family', 'getFamilyRegistry works');

    const billing = await adminService.getFamilyBilling(admin, Number(f.id));
    check(Array.isArray(billing.data?.grants), 'getFamilyBilling works');

    const { rows: [op] } = await admin.query(
      `SELECT id FROM admin_operators WHERE firebase_uid = 'check-admin-role'`);
    check(Number(op?.id) === Number(u.id), 'admin_operators finds the operator');

    await admin.query('BEGIN');
    const notice = await adminService.requestInactivityNotice(admin, Number(u.id), Number(f.id));
    check(notice.data?.familyId === Number(f.id), 'requestInactivityNotice queues and audits');
    const plans = await adminService.listPlans(admin);
    const planCode = plans.data.plans[0]?.code;
    if (planCode) {
      const grant = await adminService.createGrant(admin, Number(u.id), Number(f.id), { planCode, reason: 'check' });
      check(Boolean(grant.data?.grant?.id), 'createGrant works');
      const revoke = await adminService.revokeGrant(admin, Number(u.id), Number(f.id), grant.data.grant.id);
      check(revoke.data?.success === true, 'revokeGrant works');
    } else {
      check(false, 'a plan exists to grant');
    }
    await admin.query('ROLLBACK');
  } finally {
    await owner.query('DELETE FROM admin_family_notices WHERE family_id = $1', [f.id]);
    await owner.query('DELETE FROM families WHERE id = $1', [f.id]);
    await owner.query('DELETE FROM users WHERE id = $1', [u.id]);
    await owner.end();
    await admin.end();
  }

  console.log(failures.length ? `\n${failures.length} check(s) failed.` : '\nAll checks passed.');
  process.exitCode = failures.length ? 1 : 0;
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
