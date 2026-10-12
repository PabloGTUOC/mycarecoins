/**
 * Family entitlements (docs/admin-family-management-plan.md Phase 3).
 *
 * The backend is the single source of truth: clients never ask a store or a
 * billing SDK what a family may do — they ask us, and this module answers by
 * merging up to three sources, most generous wins:
 *
 *   1. the default plan (baseline every family has),
 *   2. the family's subscription plan, only while in good standing
 *      (trialing / active / in_grace),
 *   3. any unrevoked, unexpired admin grants (comps/trials).
 *
 * Limit semantics: a plan's `limits` JSONB maps limit keys (max_members,
 * max_actors, max_active_rewards, …) to integers; an absent key means
 * unlimited for that source, and unlimited from any source wins the merge.
 *
 * Status semantics: canceled/expired/paused subscriptions simply stop
 * conferring benefits (graceful downgrade to the default plan). Only
 * `past_due` — payment owed beyond the store's grace window — puts the
 * family in read-only mode via assertFamilyWritable.
 */

import { serviceError } from '../utils/httpError.js';

const GOOD_STANDING = new Set(['trialing', 'active', 'in_grace']);

function mergeLimits(sources) {
  // Union of keys; a source omitting a key is unlimited for it, and
  // unlimited from any source wins — such keys are simply left out.
  const merged = {};
  const keys = new Set(sources.flatMap(s => Object.keys(s.limits ?? {})));
  for (const key of keys) {
    let value = null;
    let bounded = true;
    for (const source of sources) {
      const v = (source.limits ?? {})[key];
      if (v === undefined || v === null) { bounded = false; break; }
      value = value === null ? Number(v) : Math.max(value, Number(v));
    }
    if (bounded) merged[key] = value;
  }
  return merged;
}

function mergeFeatures(sources) {
  // Opposite polarity to limits: a feature is on if ANY source turns it on.
  const merged = {};
  for (const source of sources) {
    for (const [key, value] of Object.entries(source.features ?? {})) {
      if (value) merged[key] = true;
    }
  }
  return merged;
}

export async function getFamilyEntitlements(client, familyId, now = () => new Date()) {
  const { rows } = await client.query(
    `SELECT p.code, p.limits, p.features, fp.status, fp.current_period_end,
            fp.platform, 'subscription' AS source
       FROM family_plans fp JOIN plans p ON p.code = fp.plan_code
      WHERE fp.family_id = $1
     UNION ALL
     SELECT p.code, p.limits, p.features, NULL, NULL, NULL, 'grant'
       FROM admin_grants g JOIN plans p ON p.code = g.plan_code
      WHERE g.family_id = $1 AND g.revoked_at IS NULL
        AND (g.expires_at IS NULL OR g.expires_at > NOW())
     UNION ALL
     SELECT p.code, p.limits, p.features, NULL, NULL, NULL, 'default'
       FROM plans p WHERE p.is_default = true`,
    [familyId]
  );

  const sub = rows.find(r => r.source === 'subscription');
  const def = rows.find(r => r.source === 'default');
  const grants = rows.filter(r => r.source === 'grant');
  // A canceled subscription was paid through the period: it keeps conferring
  // benefits until current_period_end, then EXPIRATION flips it to expired.
  const subGood = Boolean(sub && (
    GOOD_STANDING.has(sub.status) ||
    (sub.status === 'canceled' && sub.current_period_end &&
      new Date(sub.current_period_end) > now())
  ));

  const sources = [
    ...(def ? [def] : []),
    ...(subGood ? [sub] : []),
    ...grants,
  ];

  return {
    planCode: subGood ? sub.code : (def?.code ?? 'free'),
    subscriptionStatus: sub?.status ?? null,
    subscribed: subGood,
    platform: sub?.platform ?? null,
    currentPeriodEnd: sub?.current_period_end ?? null,
    suspended: sub?.status === 'past_due',
    grantCodes: grants.map(g => g.code),
    // No sources at all (pre-migration DB) merges to {} = everything unlimited.
    limits: mergeLimits(sources),
    features: mergeFeatures(sources),
  };
}

// Soft-enforcement helper (rollout per plan §3.4: warn first, harden in
// Phase 4). Call with the count AFTER the operation: warns once the family
// is strictly over the merged limit, else null.
export function limitWarning(entitlements, limitKey, resultingCount, warning) {
  const limit = entitlements.limits[limitKey];
  if (limit == null) return null;
  return Number(resultingCount) > limit ? warning : null;
}

// Read-only gate for families whose subscription payment is owed. Call
// BEFORE any mutation — withTransaction only rolls back on throw, so a
// gate returned after the write would not undo it.
export async function assertFamilyWritable(client, familyId) {
  const { rows } = await client.query(
    `SELECT status FROM family_plans WHERE family_id = $1`,
    [familyId]
  );
  if (rows.length && rows[0].status === 'past_due') {
    return serviceError(
      402,
      'subscriptionPaymentPastDue',
      'The family subscription payment is past due. The family is read-only until billing is resolved.'
    );
  }
  return null;
}
