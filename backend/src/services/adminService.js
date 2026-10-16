/**
 * Platform admin service (docs/admin-family-management-plan.md).
 *
 * PRIVACY BOUNDARY — read before adding queries here:
 * this module may only return registry-level data about families
 * (id, name, created_at, member counts, heartbeat, plan/billing state).
 * It must never select or join member identities (users.email,
 * users.display_name, family_members.alias, …) or family content
 * (activities, coin_ledger, marketplace_rewards, absences).
 * tests/adminService.test.js enforces this on every response shape.
 *
 * Family data comes through the admin_family_registry view
 * (scripts/migrate-admin-console.sql), never the base tables: the operator
 * console's API runs as a database role that can read nothing else.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

// Heartbeat buckets (plan §3.2): active ≤ 30 days, dormant 30–90, inactive > 90.
export function heartbeatBucket(lastActiveAt, nowMs = Date.now()) {
  if (!lastActiveAt) return 'inactive';
  const days = (nowMs - new Date(lastActiveAt).getTime()) / DAY_MS;
  if (days <= 30) return 'active';
  if (days <= 90) return 'dormant';
  return 'inactive';
}

const STATUS_CLAUSES = {
  active: `f.last_active_at > NOW() - INTERVAL '30 days'`,
  dormant: `f.last_active_at <= NOW() - INTERVAL '30 days' AND f.last_active_at > NOW() - INTERVAL '90 days'`,
  inactive: `f.last_active_at <= NOW() - INTERVAL '90 days'`,
};

// Explicit mapping is the leak barrier: only these fields ever leave this
// module, no matter what a query happens to return.
function toRegistryEntry(row, nowMs) {
  return {
    id: Number(row.id),
    name: row.name,
    createdAt: row.created_at,
    lastActiveAt: row.last_active_at,
    memberCount: Number(row.member_count ?? 0),
    pendingMemberCount: Number(row.pending_member_count ?? 0),
    actorCount: Number(row.actor_count ?? 0),
    status: heartbeatBucket(row.last_active_at, nowMs),
    planCode: row.plan_code ?? null,
    subscriptionStatus: row.subscription_status ?? null,
  };
}

export async function listFamilies(client, { search = '', status = '', page = 1, pageSize = 20 } = {}, nowMs = Date.now()) {
  const size = Math.min(Math.max(1, Number(pageSize) || 20), 100);
  const p = Math.max(1, Number(page) || 1);

  const where = [];
  const params = [];
  if (search) {
    params.push(`%${search}%`, String(search));
    where.push(`(f.name ILIKE $${params.length - 1} OR f.id::text = $${params.length})`);
  }
  if (STATUS_CLAUSES[status]) where.push(STATUS_CLAUSES[status]);
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  params.push(size, (p - 1) * size);
  const { rows } = await client.query(
    `SELECT f.id, f.name, f.created_at, f.last_active_at,
            f.plan_code, f.subscription_status, f.member_count,
            f.pending_member_count, f.actor_count,
            COUNT(*) OVER() AS total
     FROM admin_family_registry f
     ${whereSql}
     ORDER BY f.last_active_at DESC, f.id
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return {
    data: {
      families: rows.map(r => toRegistryEntry(r, nowMs)),
      page: p,
      pageSize: size,
      total: rows.length ? Number(rows[0].total) : 0,
    },
  };
}

export async function getFamilyRegistry(client, familyId, nowMs = Date.now()) {
  const { rows } = await client.query(
    `SELECT id, name, created_at, last_active_at, plan_code, subscription_status,
            member_count, pending_member_count, actor_count
     FROM admin_family_registry
     WHERE id = $1`,
    [familyId]
  );
  if (!rows.length) return { error: { code: 404, message: 'Family not found.' } };

  return {
    data: toRegistryEntry(rows[0], nowMs),
  };
}

// Records the intent to nudge an inactive family and queues the notice. The
// public backend sends the push (src/services/noticeOutbox.js): the system
// contacts the caregivers; the admin never sees who they are.
export async function requestInactivityNotice(client, adminId, familyId) {
  const result = await getFamilyRegistry(client, familyId);
  if (result.error) return result;

  await client.query(
    `INSERT INTO admin_family_notices (family_id, kind, requested_by) VALUES ($1, 'inactive', $2)`,
    [familyId, adminId]
  );

  await logAdminAction(client, adminId, 'family.notify_inactive', {
    targetType: 'family',
    targetId: familyId,
    payload: { status: result.data.status },
  });
  return { data: { familyId: result.data.id, status: result.data.status } };
}

// ─── Plan catalog ─────────────────────────────────────────────────────────────

const PLAN_CODE_RE = /^[a-z0-9_-]{1,40}$/;

function toPlan(row) {
  return {
    code: row.code,
    name: row.name,
    priceCents: Number(row.price_cents),
    currency: row.currency,
    billingPeriod: row.billing_period,
    limits: row.limits ?? {},
    features: row.features ?? {},
    isDefault: row.is_default,
    active: row.active,
  };
}

function validatePlanFields({ limits, features, priceCents }) {
  if (priceCents !== undefined && (!Number.isInteger(Number(priceCents)) || Number(priceCents) < 0)) {
    return 'priceCents must be a non-negative integer.';
  }
  if (limits !== undefined) {
    if (typeof limits !== 'object' || limits === null || Array.isArray(limits)) return 'limits must be an object.';
    for (const [k, v] of Object.entries(limits)) {
      if (v !== null && (!Number.isInteger(Number(v)) || Number(v) < 0)) {
        return `limits.${k} must be a non-negative integer or null.`;
      }
    }
  }
  if (features !== undefined && (typeof features !== 'object' || features === null || Array.isArray(features))) {
    return 'features must be an object.';
  }
  return null;
}

export async function listPlans(client) {
  const { rows } = await client.query(
    `SELECT code, name, price_cents, currency, billing_period, limits, features, is_default, active
     FROM plans ORDER BY price_cents, code`
  );
  return { data: { plans: rows.map(toPlan) } };
}

export async function createPlan(client, adminId, { code, name, priceCents = 0, currency = 'EUR', billingPeriod = 'monthly', limits = {}, features = {}, isDefault = false, active = true }) {
  if (!PLAN_CODE_RE.test(String(code ?? ''))) {
    return { error: { code: 400, message: 'code must be 1-40 chars of a-z, 0-9, _ or -.' } };
  }
  const invalid = validatePlanFields({ limits, features, priceCents });
  if (invalid) return { error: { code: 400, message: invalid } };

  if (isDefault) await client.query(`UPDATE plans SET is_default = false WHERE is_default = true`);

  const { rows, rowCount } = await client.query(
    `INSERT INTO plans (code, name, price_cents, currency, billing_period, limits, features, is_default, active)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     ON CONFLICT (code) DO NOTHING
     RETURNING code, name, price_cents, currency, billing_period, limits, features, is_default, active`,
    [code, name, Number(priceCents), currency, billingPeriod,
     JSON.stringify(limits), JSON.stringify(features), Boolean(isDefault), Boolean(active)]
  );
  if (!rowCount) return { error: { code: 409, message: 'A plan with this code already exists.' } };

  await logAdminAction(client, adminId, 'plan.create', {
    targetType: 'plan', targetId: code, payload: { name, priceCents, limits, features, isDefault, active },
  });
  return { data: { plan: toPlan(rows[0]) } };
}

const PLAN_PATCH_COLUMNS = {
  name: 'name',
  priceCents: 'price_cents',
  currency: 'currency',
  billingPeriod: 'billing_period',
  limits: 'limits',
  features: 'features',
  isDefault: 'is_default',
  active: 'active',
};

export async function updatePlan(client, adminId, code, patch) {
  const invalid = validatePlanFields(patch);
  if (invalid) return { error: { code: 400, message: invalid } };

  const sets = [];
  const params = [];
  for (const [field, column] of Object.entries(PLAN_PATCH_COLUMNS)) {
    if (patch[field] === undefined) continue;
    const value = (field === 'limits' || field === 'features')
      ? JSON.stringify(patch[field])
      : patch[field];
    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }
  if (!sets.length) return { error: { code: 400, message: 'Nothing to update.' } };

  if (patch.isDefault === true) {
    await client.query(`UPDATE plans SET is_default = false WHERE is_default = true AND code <> $1`, [code]);
  }

  params.push(code);
  const { rows } = await client.query(
    `UPDATE plans SET ${sets.join(', ')} WHERE code = $${params.length}
     RETURNING code, name, price_cents, currency, billing_period, limits, features, is_default, active`,
    params
  );
  if (!rows.length) return { error: { code: 404, message: 'Plan not found.' } };

  await logAdminAction(client, adminId, 'plan.update', {
    targetType: 'plan', targetId: code, payload: patch,
  });
  return { data: { plan: toPlan(rows[0]) } };
}

// ─── Family billing (registry-safe: subscription state, grants and event
//     metadata only — never raw provider payloads, never member identities) ──

export async function getFamilyBilling(client, familyId) {
  const { rows: famRows } = await client.query(`SELECT id FROM admin_family_registry WHERE id = $1`, [familyId]);
  if (!famRows.length) return { error: { code: 404, message: 'Family not found.' } };

  const { rows: planRows } = await client.query(
    `SELECT plan_code, status, current_period_end, platform, provider, provider_subscription_id, updated_at,
            billing_owner_user_id
     FROM family_plans WHERE family_id = $1`,
    [familyId]
  );
  const { rows: grantRows } = await client.query(
    `SELECT id, plan_code, reason, expires_at, revoked_at, created_at, granted_by
     FROM admin_grants WHERE family_id = $1 ORDER BY created_at DESC`,
    [familyId]
  );
  const { rows: eventRows } = await client.query(
    `SELECT id, provider, event_type, processed, created_at
     FROM billing_events WHERE family_id = $1 ORDER BY created_at DESC LIMIT 20`,
    [familyId]
  );

  const sub = planRows[0];
  return {
    data: {
      subscription: sub ? {
        planCode: sub.plan_code,
        status: sub.status,
        currentPeriodEnd: sub.current_period_end,
        platform: sub.platform,
        provider: sub.provider,
        providerSubscriptionId: sub.provider_subscription_id,
        updatedAt: sub.updated_at,
        billingOwnerUserId: sub.billing_owner_user_id != null ? Number(sub.billing_owner_user_id) : null,
      } : null,
      grants: grantRows.map(g => ({
        id: Number(g.id),
        planCode: g.plan_code,
        reason: g.reason,
        expiresAt: g.expires_at,
        revokedAt: g.revoked_at,
        createdAt: g.created_at,
        grantedBy: Number(g.granted_by),
      })),
      recentEvents: eventRows.map(e => ({
        id: Number(e.id),
        provider: e.provider,
        eventType: e.event_type,
        processed: e.processed,
        createdAt: e.created_at,
      })),
    },
  };
}

// ─── Grants ───────────────────────────────────────────────────────────────────

export async function createGrant(client, adminId, familyId, { planCode, reason, expiresAt }) {
  const { rows: famRows } = await client.query(`SELECT id FROM admin_family_registry WHERE id = $1`, [familyId]);
  if (!famRows.length) return { error: { code: 404, message: 'Family not found.' } };

  const { rows: planRows } = await client.query(
    `SELECT code FROM plans WHERE code = $1 AND active = true`, [planCode]
  );
  if (!planRows.length) return { error: { code: 404, message: 'Plan not found or inactive.' } };

  const { rows } = await client.query(
    `INSERT INTO admin_grants (family_id, plan_code, granted_by, reason, expires_at)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, plan_code, reason, expires_at, revoked_at, created_at, granted_by`,
    [familyId, planCode, adminId, reason?.trim() || null, expiresAt ? new Date(expiresAt) : null]
  );

  await logAdminAction(client, adminId, 'grant.create', {
    targetType: 'family', targetId: familyId, payload: { planCode, reason, expiresAt },
  });
  return {
    data: {
      grant: {
        id: Number(rows[0].id),
        planCode: rows[0].plan_code,
        reason: rows[0].reason,
        expiresAt: rows[0].expires_at,
        revokedAt: rows[0].revoked_at,
        createdAt: rows[0].created_at,
        grantedBy: Number(rows[0].granted_by),
      },
    },
  };
}

export async function revokeGrant(client, adminId, familyId, grantId) {
  const { rowCount } = await client.query(
    `UPDATE admin_grants SET revoked_at = NOW()
     WHERE id = $1 AND family_id = $2 AND revoked_at IS NULL`,
    [grantId, familyId]
  );
  if (!rowCount) return { error: { code: 404, message: 'Active grant not found.' } };

  await logAdminAction(client, adminId, 'grant.revoke', {
    targetType: 'family', targetId: familyId, payload: { grantId },
  });
  return { data: { success: true } };
}

// Every mutating admin call writes exactly one audit row, inside the same
// transaction as the mutation itself.
export async function logAdminAction(client, adminId, action, { targetType, targetId, payload } = {}) {
  await client.query(
    `INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, payload)
     VALUES ($1, $2, $3, $4, $5)`,
    [
      adminId,
      action,
      targetType ?? 'none',
      targetId == null ? null : String(targetId),
      payload == null ? null : JSON.stringify(payload),
    ]
  );
}
