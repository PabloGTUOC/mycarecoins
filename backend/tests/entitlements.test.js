import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  getFamilyEntitlements, limitWarning, assertFamilyWritable,
} from '../src/services/entitlementService.js';
import {
  listPlans, createPlan, updatePlan, getFamilyBilling, createGrant, revokeGrant,
} from '../src/services/adminService.js';

function mockClient(responses) {
  let idx = 0;
  const calls = [];
  return {
    async query(sql, params) {
      calls.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      if (idx >= responses.length) throw new Error(`Unexpected query #${idx}: ${sql.trim().slice(0, 60)}`);
      const resp = responses[idx++];
      if (resp instanceof Error) throw resp;
      return resp;
    },
    _calls: calls,
  };
}

const ok = (rows = []) => ({ rows, rowCount: rows.length });
const empty = () => ({ rows: [], rowCount: 0 });

const src = (source, code, { limits = {}, features = {}, status = null } = {}) =>
  ({ source, code, limits, features, status });

// ─── getFamilyEntitlements ──────────────────────────────────────────────────

describe('getFamilyEntitlements', () => {
  test('default plan only: baseline limits, not suspended', async () => {
    const client = mockClient([ok([src('default', 'free', { limits: { max_members: 4 } })])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.equal(ent.planCode, 'free');
    assert.equal(ent.suspended, false);
    assert.deepEqual(ent.limits, { max_members: 4 });
  });

  test('good-standing subscription raises the baseline (most generous wins)', async () => {
    const client = mockClient([ok([
      src('default', 'free', { limits: { max_members: 4, max_actors: 2 } }),
      src('subscription', 'plus', { limits: { max_members: 15, max_actors: 10 }, status: 'active' }),
    ])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.equal(ent.planCode, 'plus');
    assert.deepEqual(ent.limits, { max_members: 15, max_actors: 10 });
  });

  test('unlimited from any source wins the merge', async () => {
    const client = mockClient([ok([
      src('default', 'free', { limits: { max_members: 4 } }),
      src('grant', 'premium', { limits: {} }), // premium: unlimited members
    ])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.equal(ent.limits.max_members, undefined);
    assert.deepEqual(ent.grantCodes, ['premium']);
  });

  test('canceled subscription keeps benefits until current_period_end', async () => {
    const future = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();
    const client = mockClient([ok([
      src('default', 'free', { limits: { max_members: 4 } }),
      { ...src('subscription', 'pro', { limits: { max_members: 15 }, status: 'canceled' }),
        current_period_end: future, platform: 'play' },
    ])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.equal(ent.subscribed, true);
    assert.equal(ent.planCode, 'pro');
    assert.equal(ent.limits.max_members, 15);
    assert.equal(ent.platform, 'play');
  });

  test('lapsed subscription downgrades gracefully to the default plan', async () => {
    const client = mockClient([ok([
      src('default', 'free', { limits: { max_members: 4 } }),
      src('subscription', 'plus', { limits: { max_members: 15 }, status: 'canceled' }),
    ])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.equal(ent.planCode, 'free');
    assert.equal(ent.suspended, false);
    assert.deepEqual(ent.limits, { max_members: 4 });
  });

  test('past_due excludes the plan AND flags suspension', async () => {
    const client = mockClient([ok([
      src('default', 'free', { limits: { max_members: 4 } }),
      src('subscription', 'plus', { limits: { max_members: 15 }, status: 'past_due' }),
    ])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.equal(ent.suspended, true);
    assert.equal(ent.subscriptionStatus, 'past_due');
    assert.deepEqual(ent.limits, { max_members: 4 });
  });

  test('in_grace still confers benefits', async () => {
    const client = mockClient([ok([
      src('default', 'free', { limits: { max_members: 4 } }),
      src('subscription', 'plus', { limits: { max_members: 15 }, status: 'in_grace' }),
    ])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.equal(ent.limits.max_members, 15);
  });

  test('features are ON if any source grants them', async () => {
    const client = mockClient([ok([
      src('default', 'free', { features: {} }),
      src('grant', 'plus', { features: { advanced_stats: true } }),
    ])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.deepEqual(ent.features, { advanced_stats: true });
  });

  test('pre-migration DB (no rows) means unlimited everything', async () => {
    const client = mockClient([ok([])]);
    const ent = await getFamilyEntitlements(client, 1);
    assert.deepEqual(ent.limits, {});
    assert.equal(ent.suspended, false);
  });
});

// ─── limitWarning / assertFamilyWritable ────────────────────────────────────

describe('limitWarning', () => {
  const ent = { limits: { max_members: 4 } };
  test('warns only when strictly over the limit', () => {
    assert.equal(limitWarning(ent, 'max_members', 5, 'member_limit_exceeded'), 'member_limit_exceeded');
    assert.equal(limitWarning(ent, 'max_members', 4, 'member_limit_exceeded'), null);
    assert.equal(limitWarning({ limits: {} }, 'max_members', 999, 'w'), null);
  });
});

describe('assertFamilyWritable', () => {
  test('402 when past_due', async () => {
    const client = mockClient([ok([{ status: 'past_due' }])]);
    const gate = await assertFamilyWritable(client, 1);
    assert.equal(gate.error.code, 402);
  });

  test('null when active or unsubscribed', async () => {
    assert.equal(await assertFamilyWritable(mockClient([ok([{ status: 'active' }])]), 1), null);
    assert.equal(await assertFamilyWritable(mockClient([empty()]), 1), null);
  });
});

// ─── plan catalog ───────────────────────────────────────────────────────────

const planRow = {
  code: 'plus', name: 'Plus', price_cents: '299', currency: 'EUR', billing_period: 'monthly',
  limits: { max_members: 15 }, features: {}, is_default: false, active: true,
};

describe('plan catalog', () => {
  test('listPlans maps snake_case rows to API shape', async () => {
    const client = mockClient([ok([planRow])]);
    const result = await listPlans(client);
    assert.deepEqual(result.data.plans[0], {
      code: 'plus', name: 'Plus', priceCents: 299, currency: 'EUR', billingPeriod: 'monthly',
      limits: { max_members: 15 }, features: {}, isDefault: false, active: true,
    });
  });

  test('createPlan rejects bad codes and bad limits', async () => {
    assert.equal((await createPlan(mockClient([]), 1, { code: 'Bad Code!', name: 'X' })).error.code, 400);
    assert.equal((await createPlan(mockClient([]), 1, {
      code: 'x', name: 'X', limits: { max_members: -1 },
    })).error.code, 400);
  });

  test('createPlan inserts, audits, and 409s on duplicates', async () => {
    const client = mockClient([ok([planRow]), empty()]); // INSERT, audit
    const result = await createPlan(client, 7, { code: 'plus', name: 'Plus', priceCents: 299, limits: { max_members: 15 } });
    assert.equal(result.data.plan.code, 'plus');
    assert.ok(client._calls[1].sql.includes('INSERT INTO admin_audit_log'));
    assert.equal(client._calls[1].params[1], 'plan.create');

    const dup = mockClient([empty()]);
    assert.equal((await createPlan(dup, 7, { code: 'plus', name: 'Plus' })).error.code, 409);
  });

  test('updatePlan patches only provided fields and audits', async () => {
    const client = mockClient([ok([planRow]), empty()]);
    const result = await updatePlan(client, 7, 'plus', { limits: { max_members: 20 } });
    assert.equal(result.data.plan.code, 'plus');
    assert.ok(client._calls[0].sql.startsWith('UPDATE plans SET limits = $1'));
    assert.equal(client._calls[1].params[1], 'plan.update');
  });

  test('updatePlan 404s on unknown plan and 400s on empty patch', async () => {
    assert.equal((await updatePlan(mockClient([empty()]), 7, 'nope', { name: 'X' })).error.code, 404);
    assert.equal((await updatePlan(mockClient([]), 7, 'plus', {})).error.code, 400);
  });
});

// ─── family billing view ────────────────────────────────────────────────────

describe('getFamilyBilling', () => {
  test('404 when family is missing', async () => {
    const result = await getFamilyBilling(mockClient([empty()]), 99);
    assert.equal(result.error.code, 404);
  });

  test('returns subscription, grants and event metadata — never payloads', async () => {
    const client = mockClient([
      ok([{ id: 1 }]),
      ok([{ plan_code: 'plus', status: 'active', current_period_end: null, platform: 'play',
            provider: 'revenuecat', provider_subscription_id: 'sub_1', updated_at: 'now',
            billing_owner_user_id: '42' }]),
      ok([{ id: '5', plan_code: 'plus', reason: 'comp', expires_at: null, revoked_at: null,
            created_at: 'now', granted_by: '7',
            rc_status: 'synced', rc_attempts: 0, rc_last_error: null, rc_synced_at: 'now' }]),
      ok([{ id: '9', provider: 'revenuecat', event_type: 'RENEWAL', processed: true,
            created_at: 'now', payload: { secret: 'raw provider payload' } }]),
    ]);
    const result = await getFamilyBilling(client, 1);
    assert.equal(result.data.subscription.planCode, 'plus');
    assert.equal(result.data.subscription.billingOwnerUserId, 42);
    assert.equal(result.data.grants[0].grantedBy, 7);
    assert.deepEqual(result.data.grants[0].rcSync, {
      status: 'synced',
      attempts: 0,
      lastError: null,
      syncedAt: 'now',
    });
    assert.deepEqual(Object.keys(result.data.recentEvents[0]).sort(),
      ['createdAt', 'eventType', 'id', 'processed', 'provider']);
  });

  test('maps billingOwnerUserId to null when unassigned', async () => {
    const client = mockClient([
      ok([{ id: 1 }]),
      ok([{ plan_code: 'free', status: 'active', current_period_end: null, platform: null,
            provider: null, provider_subscription_id: null, updated_at: 'now',
            billing_owner_user_id: null }]),
      ok([]),
      ok([]),
    ]);
    const result = await getFamilyBilling(client, 1);
    assert.equal(result.data.subscription.billingOwnerUserId, null);
  });
});

// ─── grants ─────────────────────────────────────────────────────────────────

describe('grants', () => {
  const grantRow = {
    id: '5', plan_code: 'plus', reason: 'beta tester', expires_at: null,
    revoked_at: null, created_at: 'now', granted_by: '7',
  };

  test('createGrant validates family and plan, inserts and audits', async () => {
    const client = mockClient([
      ok([{ id: 1 }]),      // family exists
      ok([{ code: 'plus' }]), // plan exists + active
      ok([grantRow]),       // INSERT admin_grants
      empty(),              // INSERT admin_rc_sync
      empty(),              // audit
    ]);
    const result = await createGrant(client, 7, 1, { planCode: 'plus', reason: 'beta tester' });
    assert.equal(result.data.grant.planCode, 'plus');
    assert.ok(client._calls[3].sql.includes('INSERT INTO admin_rc_sync'));
    assert.equal(client._calls[3].params[0], 5);
    assert.equal(client._calls[3].params[1], 'family_1');
    assert.equal(client._calls[4].params[1], 'grant.create');

    assert.equal((await createGrant(mockClient([empty()]), 7, 99, { planCode: 'plus' })).error.code, 404);
    assert.equal((await createGrant(mockClient([ok([{ id: 1 }]), empty()]), 7, 1, { planCode: 'nope' })).error.code, 404);
  });

  test('revokeGrant stamps revoked_at once and audits', async () => {
    const client = mockClient([
      { rows: [], rowCount: 1 }, // UPDATE admin_grants
      empty(),                   // upsert admin_rc_sync
      empty(),                   // audit
    ]);
    const result = await revokeGrant(client, 7, 1, 5);
    assert.equal(result.data.success, true);
    assert.ok(client._calls[1].sql.includes('admin_rc_sync'));
    assert.equal(client._calls[1].params[0], 5);
    assert.equal(client._calls[1].params[1], 'family_1');
    assert.equal(client._calls[2].params[1], 'grant.revoke');

    assert.equal((await revokeGrant(mockClient([empty()]), 7, 1, 5)).error.code, 404);
  });
});
