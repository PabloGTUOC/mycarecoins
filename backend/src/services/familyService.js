import { assertActiveMember } from '../db/users.js';
import {
  insertDefaultActivities,
  insertStarterTasks,
  validateStarterTasks,
} from '../db/defaultActivities.js';

export async function listFamilies(client, userId) {
  const { rows } = await client.query(
    `SELECT f.id, f.name, f.monthly_coin_budget, fm.role, fm.coin_balance
     FROM family_members fm
     JOIN families f ON f.id = fm.family_id
     WHERE fm.user_id = $1
     ORDER BY f.created_at DESC`,
    [userId]
  );
  return { data: { families: rows } };
}

export async function getFamilyBudget(client, userId, familyId) {
  if (!await assertActiveMember(client, familyId, userId)) {
    return { error: { code: 403, message: 'Not a family member or family not found.' } };
  }
  const { rows } = await client.query(`
    SELECT f.monthly_coin_budget,
      COALESCE((
        SELECT SUM(coin_value) FROM activities
        WHERE family_id = $1 AND category = 'care' AND is_template = false AND status = 'completed'
          AND date_trunc('month', starts_at) = date_trunc('month', NOW())
      ), 0)::int as used_this_month
    FROM families f WHERE f.id = $1
  `, [familyId]);
  if (!rows.length) return { error: { code: 404, message: 'Family not found.' } };
  const d = rows[0];
  return {
    data: {
      monthlyBudget: d.monthly_coin_budget,
      usedThisMonth: d.used_this_month,
      remainingBudget: Math.max(0, d.monthly_coin_budget - d.used_this_month),
      baseRatePerHour: parseFloat((d.monthly_coin_budget / 720).toFixed(2)),
    },
  };
}

export async function createFamily(client, user, { name, mainCaretakerName, alias, caretakers = [], objectsOfCare = [], starterTasks }) {
  // Validate before any write: the seeding happens at the end of this
  // function, and withTransaction only rolls back on throw.
  if (starterTasks !== undefined) {
    const invalid = validateStarterTasks(starterTasks);
    if (invalid) return { error: { code: 400, message: invalid } };
  }

  let monthlyCoinBudget = objectsOfCare.reduce((sum, obj) => {
    return sum + (obj.careTime === 'full_time' ? 720 : 360);
  }, 0);
  if (monthlyCoinBudget === 0) monthlyCoinBudget = 1000;

  if (mainCaretakerName?.trim()) {
    await client.query(`UPDATE users SET display_name = $1 WHERE id = $2`, [mainCaretakerName.trim(), user.id]);
    user.display_name = mainCaretakerName.trim();
  }

  const { rows: famRows } = await client.query(
    `INSERT INTO families (name, monthly_coin_budget, created_by)
     VALUES ($1, $2, $3)
     RETURNING id, name, monthly_coin_budget`,
    [name.trim(), monthlyCoinBudget, user.id]
  );
  const famId = famRows[0].id;

  // Every family starts on the default plan (no-op if none is seeded yet).
  await client.query(
    `INSERT INTO family_plans (family_id, plan_code, provider)
     SELECT $1, code, 'system' FROM plans WHERE is_default = true LIMIT 1
     ON CONFLICT (family_id) DO NOTHING`,
    [famId]
  );

  await client.query(
    `INSERT INTO family_members (family_id, user_id, role, status, alias)
     VALUES ($1, $2, 'caregiver', 'active', $3)`,
    [famId, user.id, alias ? alias.trim() : null]
  );
  await client.query(
    `INSERT INTO actors (family_id, user_id, actor_type, name) VALUES ($1, $2, 'person', $3)`,
    [famId, user.id, user.display_name]
  );

  for (const ct of caretakers) {
    if (ct.email?.trim()) {
      await client.query(
        `INSERT INTO family_invitations (family_id, email, name, invited_by)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (family_id, email) DO NOTHING`,
        [famId, ct.email.trim(), ct.name?.trim() || null, user.id]
      );
    }
  }
  for (const obj of objectsOfCare) {
    if (obj.name?.trim()) {
      await client.query(
        `INSERT INTO actors (family_id, actor_type, name, care_time) VALUES ($1, $2, $3, $4)`,
        [famId, obj.type || 'child', obj.name.trim(), obj.careTime || 'full_time']
      );
    }
  }

  // New clients send a localized catalogue chosen in the setup wizard; an
  // empty array means "start empty". Clients that omit the field (old app
  // builds, scripted API calls) keep the legacy English defaults.
  if (starterTasks !== undefined) {
    await insertStarterTasks(client, famId, user.id, starterTasks, monthlyCoinBudget);
  } else {
    await insertDefaultActivities(client, famId, user.id, objectsOfCare);
  }
  return { data: famRows[0] };
}

export async function deleteFamily(client, user, familyId) {
  const { rows: caregivers } = await client.query(
    `SELECT u.id, u.email, u.display_name
     FROM family_members fm JOIN users u ON u.id = fm.user_id
     WHERE fm.family_id = $1 AND fm.role = 'caregiver' AND fm.status = 'active'`,
    [familyId]
  );
  const { rows: familyRows } = await client.query(`SELECT name FROM families WHERE id = $1`, [familyId]);
  if (!familyRows.length) return { error: { code: 404, message: 'Family not found.' } };
  const familyName = familyRows[0].name;

  if (caregivers.length <= 1) {
    await client.query(`DELETE FROM families WHERE id = $1`, [familyId]);
    return { data: { success: true, deleted: true } };
  }

  const { rows: existing } = await client.query(
    `SELECT id FROM family_deletion_requests WHERE family_id = $1 AND status = 'pending'`,
    [familyId]
  );
  if (existing.length > 0) {
    return { error: { code: 409, message: 'A deletion request is already pending.' } };
  }

  const { rows: reqRows } = await client.query(
    `INSERT INTO family_deletion_requests (family_id, requested_by) VALUES ($1, $2) RETURNING id`,
    [familyId, user.id]
  );
  const reqId = reqRows[0].id;

  for (const cg of caregivers) {
    if (cg.id !== user.id) {
      await client.query(
        `INSERT INTO family_deletion_approvals (request_id, caregiver_id) VALUES ($1, $2)`,
        [reqId, cg.id]
      );
    }
  }

  return { data: { success: true, pendingApproval: true }, familyId, requesterId: user.id, caregivers, familyName };
}

export async function getDeletionRequests(client, familyId) {
  const { rows: reqs } = await client.query(
    `SELECT r.id, r.status, r.created_at, u.display_name as requested_by_name
     FROM family_deletion_requests r JOIN users u ON u.id = r.requested_by
     WHERE r.family_id = $1 AND r.status = 'pending'`,
    [familyId]
  );
  if (!reqs.length) return { data: { deletionRequests: [] } };
  const reqData = reqs[0];
  const { rows: approvals } = await client.query(
    `SELECT a.status, u.display_name as caregiver_name, a.caregiver_id
     FROM family_deletion_approvals a JOIN users u ON u.id = a.caregiver_id
     WHERE a.request_id = $1`,
    [reqData.id]
  );
  reqData.approvals = approvals;
  return { data: { deletionRequests: [reqData] } };
}

export async function approveDeletion(client, userId, familyId, requestId) {
  const { rows: reqCheck } = await client.query(
    `SELECT id FROM family_deletion_requests WHERE id = $1 AND family_id = $2`,
    [requestId, familyId]
  );
  if (!reqCheck.length) return { error: { code: 404, message: 'Deletion request not found.' } };

  const { rows: approvalRows } = await client.query(
    `UPDATE family_deletion_approvals SET status = 'approved', responded_at = NOW()
     WHERE request_id = $1 AND caregiver_id = $2 RETURNING id`,
    [requestId, userId]
  );
  if (!approvalRows.length) return { error: { code: 404, message: 'Approval record not found or not yours.' } };

  const { rows: pending } = await client.query(
    `SELECT id FROM family_deletion_approvals WHERE request_id = $1 AND status != 'approved'`,
    [requestId]
  );
  if (pending.length === 0) {
    await client.query(`UPDATE family_deletion_requests SET status = 'approved' WHERE id = $1`, [requestId]);
    await client.query(`DELETE FROM families WHERE id = $1`, [familyId]);
    return { data: { success: true, deleted: true } };
  }
  return { data: { success: true, pendingApproval: true } };
}

export async function rejectDeletion(client, userId, familyId, requestId) {
  const { rows: reqCheck } = await client.query(
    `SELECT id FROM family_deletion_requests WHERE id = $1 AND family_id = $2`,
    [requestId, familyId]
  );
  if (!reqCheck.length) return { error: { code: 404, message: 'Deletion request not found.' } };

  const { rows: approvalRows } = await client.query(
    `UPDATE family_deletion_approvals SET status = 'rejected', responded_at = NOW()
     WHERE request_id = $1 AND caregiver_id = $2 RETURNING id`,
    [requestId, userId]
  );
  if (!approvalRows.length) return { error: { code: 404, message: 'Approval record not found or not yours.' } };

  await client.query(`UPDATE family_deletion_requests SET status = 'rejected' WHERE id = $1`, [requestId]);
  return { data: { success: true } };
}
