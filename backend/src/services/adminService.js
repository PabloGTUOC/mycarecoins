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
    `SELECT g.id, g.plan_code, g.reason, g.expires_at, g.revoked_at, g.created_at, g.granted_by,
            s.status AS rc_status, s.attempts AS rc_attempts, s.last_error AS rc_last_error,
            s.synced_at AS rc_synced_at
     FROM admin_grants g
     LEFT JOIN admin_rc_sync s ON s.grant_id = g.id
     WHERE g.family_id = $1 ORDER BY g.created_at DESC`,
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
        rcSync: g.rc_status ? {
          status: g.rc_status,
          attempts: Number(g.rc_attempts ?? 0),
          lastError: g.rc_last_error ?? null,
          syncedAt: g.rc_synced_at ?? null,
        } : null,
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
  const grant = rows[0];

  await client.query(
    `INSERT INTO admin_rc_sync (grant_id, rc_customer_id, action, status)
     VALUES ($1, $2, 'grant', 'pending')`,
    [Number(grant.id), `family_${familyId}`]
  );

  await logAdminAction(client, adminId, 'grant.create', {
    targetType: 'family', targetId: familyId, payload: { planCode, reason, expiresAt },
  });
  return {
    data: {
      grant: {
        id: Number(grant.id),
        planCode: grant.plan_code,
        reason: grant.reason,
        expiresAt: grant.expires_at,
        revokedAt: grant.revoked_at,
        createdAt: grant.created_at,
        grantedBy: Number(grant.granted_by),
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

  await client.query(
    `INSERT INTO admin_rc_sync (grant_id, rc_customer_id, action, status, attempts, last_error, updated_at)
     VALUES ($1, $2, 'revoke', 'pending', 0, NULL, NOW())
     ON CONFLICT (grant_id) DO UPDATE SET
       action = 'revoke',
       status = 'pending',
       attempts = 0,
       last_error = NULL,
       updated_at = NOW()`,
    [Number(grantId), `family_${familyId}`]
  );

  await logAdminAction(client, adminId, 'grant.revoke', {
    targetType: 'family', targetId: familyId, payload: { grantId },
  });
  return { data: { success: true } };
}

export async function resetGrantRcSync(client, adminId, familyId, grantId) {
  const { rows: grantRows } = await client.query(
    `SELECT id FROM admin_grants WHERE id = $1 AND family_id = $2`,
    [grantId, familyId]
  );
  if (!grantRows.length) return { error: { code: 404, message: 'Grant not found in family.' } };

  const { rows, rowCount } = await client.query(
    `UPDATE admin_rc_sync
     SET status = 'pending',
         attempts = 0,
         last_error = NULL,
         updated_at = NOW()
     WHERE grant_id = $1
     RETURNING status, attempts, last_error, synced_at`,
    [grantId]
  );
  if (!rowCount) {
    return { error: { code: 404, message: 'Grant has no RevenueCat sync record.' } };
  }

  await logAdminAction(client, adminId, 'grant.rc_retry', {
    targetType: 'grant', targetId: grantId, payload: { familyId },
  });

  return { data: { syncRow: rows[0] } };
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

// ─── Console Overview (MP3b) ──────────────────────────────────────────────────

export async function getOverview(client, { nowMs = Date.now() } = {}) {
  const { rows: famCountRows } = await client.query(`
    SELECT
      COUNT(*)::int AS total,
      COUNT(*) FILTER (WHERE ${STATUS_CLAUSES.active})::int AS active,
      COUNT(*) FILTER (WHERE ${STATUS_CLAUSES.dormant})::int AS dormant,
      COUNT(*) FILTER (WHERE f.last_active_at IS NULL OR ${STATUS_CLAUSES.inactive})::int AS inactive
    FROM admin_family_registry f
  `);
  const famCount = famCountRows[0] || {};

  const { rows: breakdownRows } = await client.query(`
    SELECT 'plan' AS dimension, COALESCE(f.plan_code, 'none') AS key, COUNT(*)::int AS count
    FROM admin_family_registry f
    GROUP BY 2
    UNION ALL
    SELECT 'status' AS dimension, COALESCE(f.subscription_status, 'none') AS key, COUNT(*)::int AS count
    FROM admin_family_registry f
    GROUP BY 2
    UNION ALL
    SELECT 'store' AS dimension, COALESCE(fp.platform, 'none') AS key, COUNT(*)::int AS count
    FROM admin_family_registry f
    LEFT JOIN family_plans fp ON fp.family_id = f.id
    GROUP BY 2
  `);

  const byPlan = {};
  const byStatus = {};
  const byStore = {};
  for (const row of breakdownRows) {
    const count = Number(row.count ?? 0);
    if (row.dimension === 'plan') byPlan[row.key] = count;
    else if (row.dimension === 'status') byStatus[row.key] = count;
    else if (row.dimension === 'store') byStore[row.key] = count;
  }

  const { rows: freeRows } = await client.query(`
    SELECT
      COUNT(*)::int AS active_grants,
      COUNT(DISTINCT family_id)::int AS families_count
    FROM admin_grants
    WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())
  `);
  const freePlan = freeRows[0] || {};

  const { rows: mirrorRows } = await client.query(`
    SELECT
      COUNT(*) FILTER (WHERE status = 'pending')::int AS pending,
      COUNT(*) FILTER (WHERE status = 'synced')::int AS synced,
      COUNT(*) FILTER (WHERE status = 'failed')::int AS failed,
      EXTRACT(EPOCH FROM (NOW() - MIN(updated_at) FILTER (WHERE status = 'pending'))) / 60 AS oldest_pending_minutes
    FROM admin_rc_sync
  `);
  const mirrorRow = mirrorRows[0] || {};

  const { rows: webhookRows } = await client.query(`
    SELECT
      MAX(created_at) AS last_event_at,
      COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days')::int AS events_last_30_days,
      COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days' AND family_id IS NULL)::int AS unattributed_last_30_days,
      COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days' AND processed = false)::int AS unprocessed_last_30_days
    FROM billing_events
  `);
  const webhookRow = webhookRows[0] || {};

  const { rows: recentIssueRows } = await client.query(`
    SELECT id, event_type, created_at
    FROM billing_events
    WHERE family_id IS NULL OR processed = false
    ORDER BY created_at DESC, id DESC
    LIMIT 10
  `);

  return {
    families: {
      total: Number(famCount.total ?? 0),
      byHeartbeat: {
        active: Number(famCount.active ?? 0),
        dormant: Number(famCount.dormant ?? 0),
        inactive: Number(famCount.inactive ?? 0),
      },
      byPlan,
      byStatus,
      byStore,
    },
    freePlans: {
      activeGrants: Number(freePlan.active_grants ?? 0),
      familiesCount: Number(freePlan.families_count ?? 0),
    },
    mirror: {
      pending: Number(mirrorRow.pending ?? 0),
      synced: Number(mirrorRow.synced ?? 0),
      failed: Number(mirrorRow.failed ?? 0),
      oldestPendingAgeMinutes: mirrorRow.oldest_pending_minutes != null
        ? Math.max(0, Math.floor(Number(mirrorRow.oldest_pending_minutes)))
        : null,
    },
    webhooks: {
      lastEventAt: webhookRow.last_event_at ? new Date(webhookRow.last_event_at).toISOString() : null,
      eventsLast30Days: Number(webhookRow.events_last_30_days ?? 0),
      unattributedLast30Days: Number(webhookRow.unattributed_last_30_days ?? 0),
      unprocessedLast30Days: Number(webhookRow.unprocessed_last_30_days ?? 0),
      recentEvents: recentIssueRows.map((r) => ({
        id: Number(r.id),
        eventType: r.event_type,
        createdAt: r.created_at ? new Date(r.created_at).toISOString() : null,
      })),
    },
  };
}

// ─── Family RevenueCat State & Mismatches (MP3c) ──────────────────────────────

export async function getFamilyRevenueCatStatus(client, familyId, rcClient, rcConfig, { nowMs = Date.now() } = {}) {
  const { rows: famRows } = await client.query(
    `SELECT id FROM admin_family_registry WHERE id = $1`,
    [familyId]
  );
  if (!famRows.length) {
    return { error: { code: 404, message: 'Family not found.' } };
  }

  const { rows: planRows } = await client.query(
    `SELECT plan_code, status, provider, billing_owner_user_id
     FROM family_plans
     WHERE family_id = $1`,
    [familyId]
  );
  const sub = planRows[0] || null;

  const { rows: grantRows } = await client.query(
    `SELECT g.id, g.plan_code, s.status AS sync_status
     FROM admin_grants g
     LEFT JOIN admin_rc_sync s ON s.grant_id = g.id
     WHERE g.family_id = $1
       AND g.revoked_at IS NULL
       AND (g.expires_at IS NULL OR g.expires_at > NOW())`,
    [familyId]
  );

  async function lookupCustomer(customerId) {
    try {
      // https://www.revenuecat.com/docs/api-v2/customer
      const raw = await rcClient.getCustomer(customerId);
      const activeItems = raw?.active_entitlements?.items || [];
      const entitlements = activeItems.map((e) => {
        const item = {
          id: e.entitlement_id ?? e.id ?? null,
          expiresAt: e.expires_at ? new Date(e.expires_at).toISOString() : null,
        };
        if (e.store != null) item.store = e.store;
        if (e.grant_type != null) item.grantType = e.grant_type;
        return item;
      });
      return {
        customerId,
        found: true,
        entitlements,
        lastSeenAt: raw.last_seen_at ? new Date(raw.last_seen_at).toISOString() : null,
      };
    } catch (err) {
      if (err.status === 404) {
        return {
          customerId,
          found: false,
          entitlements: [],
          lastSeenAt: null,
        };
      }
      throw err;
    }
  }

  const familyCustomerId = `family_${familyId}`;
  const familyCustomer = await lookupCustomer(familyCustomerId);

  let billingOwnerCustomer = null;
  if (sub?.billing_owner_user_id != null) {
    billingOwnerCustomer = await lookupCustomer(String(sub.billing_owner_user_id));
  }

  const entitlementId = rcConfig?.entitlementId;

  const hasActiveGrant = grantRows.length > 0;
  const hasSyncedActiveGrant = grantRows.some((g) => g.sync_status === 'synced');

  const familyHasEntitlement = Boolean(
    familyCustomer.found &&
    familyCustomer.entitlements.some(
      (e) => (!entitlementId || e.id === entitlementId) && (!e.expiresAt || new Date(e.expiresAt).getTime() > nowMs)
    )
  );

  const billingOwnerHasEntitlement = Boolean(
    billingOwnerCustomer?.found &&
    billingOwnerCustomer.entitlements.some(
      (e) => (!entitlementId || e.id === entitlementId) && (!e.expiresAt || new Date(e.expiresAt).getTime() > nowMs)
    )
  );

  const isRcSubscription = sub?.provider === 'revenuecat' && ['active', 'trialing', 'in_grace'].includes(sub?.status);

  const mismatches = [];

  // 1. freePlanNotMirrored: the family has an active grant whose sync row is synced,
  // but the family customer has no active RC_ENTITLEMENT_ID entitlement.
  if (hasSyncedActiveGrant && !familyHasEntitlement) {
    mismatches.push({
      code: 'freePlanNotMirrored',
      message: 'The family has an active grant synced in our database, but no active entitlement exists in RevenueCat.',
    });
  }

  // 2. mirrorStale: the family has no active grant, but the family customer still has
  // the entitlement active.
  if (!hasActiveGrant && familyHasEntitlement) {
    mismatches.push({
      code: 'mirrorStale',
      message: 'The family has no active grant in our database, but the entitlement is still active in RevenueCat.',
    });
  }

  // 3. subscriptionMissingInRevenueCat: family_plans says active/trialing/in_grace from
  // provider revenuecat, but the billing owner customer has no active entitlement.
  if (isRcSubscription && !billingOwnerHasEntitlement) {
    mismatches.push({
      code: 'subscriptionMissingInRevenueCat',
      message: 'The subscription is active in CareCoins via RevenueCat, but no active entitlement exists on the billing owner in RevenueCat.',
    });
  }

  // 4. subscriptionMissingHere: the billing owner customer has the entitlement active
  // but family_plans is not in one of those statuses (a missed webhook).
  if (billingOwnerHasEntitlement && !isRcSubscription) {
    mismatches.push({
      code: 'subscriptionMissingHere',
      message: 'The billing owner customer has an active entitlement in RevenueCat, but the family does not have an active subscription in CareCoins.',
    });
  }

  return {
    data: {
      familyCustomer,
      billingOwnerCustomer,
      mismatches,
    },
  };
}
