import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { syncPending } from '../src/admin/rcSync.js';
import { RevenueCatError } from '../src/admin/revenuecat.js';

function mockDb(queryHandler) {
  return {
    async connect() {
      return {
        query: queryHandler,
        release() {},
      };
    },
    query: queryHandler,
  };
}

describe('syncPending', () => {
  const entitlementId = 'ent_pro';
  const now = new Date('2026-10-16T12:00:00Z');

  test('grant sync: calls ensureCustomer with array attributes and grantEntitlement with expiry, marks synced', async () => {
    const grantRow = {
      grant_id: '5',
      rc_customer_id: 'family_42',
      action: 'grant',
      status: 'pending',
      attempts: 0,
      family_id: '42',
      expires_at: '2026-12-31T00:00:00Z',
      revoked_at: null,
    };

    const queries = [];
    let queryIdx = 0;
    const db = mockDb(async (sql, params) => {
      queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      queryIdx++;
      if (sql.includes('BEGIN') || sql.includes('COMMIT')) return { rows: [] };
      if (sql.includes('SELECT s.grant_id')) {
        if (queryIdx === 2) return { rows: [grantRow] };
        return { rows: [] };
      }
      if (sql.includes('UPDATE admin_rc_sync')) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [] };
    });

    const rcCalls = [];
    const rc = {
      async ensureCustomer(customerId, attributes) {
        rcCalls.push({ method: 'ensureCustomer', customerId, attributes });
      },
      async grantEntitlement(customerId, entId, expiresAtMs) {
        rcCalls.push({ method: 'grantEntitlement', customerId, entId, expiresAtMs });
      },
      async revokeGrantedEntitlement() {},
    };

    const result = await syncPending(db, rc, { entitlementId, now });
    assert.equal(result.processed, 1);
    assert.deepEqual(result.results, [{ grantId: 5, status: 'synced' }]);

    assert.equal(rcCalls.length, 2);
    assert.deepEqual(rcCalls[0], {
      method: 'ensureCustomer',
      customerId: 'family_42',
      attributes: [{ name: 'family_id', value: '42' }],
    });
    assert.equal(rcCalls[1].method, 'grantEntitlement');
    assert.equal(rcCalls[1].customerId, 'family_42');
    assert.equal(rcCalls[1].entId, entitlementId);
    assert.equal(rcCalls[1].expiresAtMs, new Date('2026-12-31T00:00:00Z').getTime());

    const updateCall = queries.find((q) => q.sql.includes('UPDATE admin_rc_sync'));
    assert.ok(updateCall.sql.includes("status = 'synced'"));
    assert.equal(updateCall.params[0], now);
    assert.equal(updateCall.params[1], '5');
  });

  test('grant sync without expiry: grants for now + 100 years', async () => {
    const lifetimeRow = {
      grant_id: '6',
      rc_customer_id: 'family_42',
      action: 'grant',
      status: 'pending',
      attempts: 0,
      family_id: '42',
      expires_at: null,
      revoked_at: null,
    };

    let queryIdx = 0;
    const db = mockDb(async (sql) => {
      queryIdx++;
      if (sql.includes('SELECT s.grant_id')) {
        return queryIdx === 2 ? { rows: [lifetimeRow] } : { rows: [] };
      }
      return { rows: [] };
    });

    let grantedExpiry = null;
    const rc = {
      async ensureCustomer() {},
      async grantEntitlement(customerId, entId, expiresAtMs) {
        grantedExpiry = expiresAtMs;
      },
      async revokeGrantedEntitlement() {},
    };

    await syncPending(db, rc, { entitlementId, now });
    const expected100y = now.getTime() + 100 * 365.25 * 24 * 60 * 60 * 1000;
    assert.equal(grantedExpiry, expected100y);
  });

  test('grant sync with past expiry: marks synced without calling RevenueCat', async () => {
    const expiredRow = {
      grant_id: '15',
      rc_customer_id: 'family_42',
      action: 'grant',
      status: 'pending',
      attempts: 0,
      family_id: '42',
      expires_at: '2026-10-15T00:00:00Z', // Before `now` (2026-10-16T12:00:00Z)
      revoked_at: null,
    };

    const queries = [];
    let queryIdx = 0;
    const db = mockDb(async (sql, params) => {
      queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      queryIdx++;
      if (sql.includes('SELECT s.grant_id')) {
        return queryIdx === 2 ? { rows: [expiredRow] } : { rows: [] };
      }
      if (sql.includes('UPDATE admin_rc_sync')) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [] };
    });

    let rcCalled = false;
    const rc = {
      async ensureCustomer() { rcCalled = true; },
      async grantEntitlement() { rcCalled = true; },
      async revokeGrantedEntitlement() { rcCalled = true; },
    };

    const result = await syncPending(db, rc, { entitlementId, now });
    assert.equal(result.processed, 1);
    assert.deepEqual(result.results, [{ grantId: 15, status: 'synced' }]);
    assert.equal(rcCalled, false);

    const updateCall = queries.find((q) => q.sql.includes('UPDATE admin_rc_sync'));
    assert.ok(updateCall.sql.includes("status = 'synced'"));
    assert.equal(updateCall.params[0], now);
    assert.equal(updateCall.params[1], '15');
  });

  test('revoke sync (one grant): calls revokeGrantedEntitlement only, marks synced', async () => {
    const revokeRow = {
      grant_id: '7',
      rc_customer_id: 'family_42',
      action: 'revoke',
      status: 'pending',
      attempts: 0,
      family_id: '42',
      expires_at: null,
      revoked_at: 'now',
    };

    let queryIdx = 0;
    const db = mockDb(async (sql) => {
      queryIdx++;
      if (sql.includes('SELECT s.grant_id')) {
        return queryIdx === 2 ? { rows: [revokeRow] } : { rows: [] };
      }
      if (sql.includes('admin_grants') && sql.includes('expires_at')) {
        // No other active grants remain
        return { rows: [] };
      }
      return { rows: [] };
    });

    const rcCalls = [];
    const rc = {
      async ensureCustomer() {},
      async grantEntitlement(customerId, entId, expiresAtMs) {
        rcCalls.push({ method: 'grant', customerId, entId, expiresAtMs });
      },
      async revokeGrantedEntitlement(customerId, entId) {
        rcCalls.push({ method: 'revoke', customerId, entId });
      },
    };

    const result = await syncPending(db, rc, { entitlementId, now });
    assert.equal(result.processed, 1);
    assert.deepEqual(rcCalls, [{ method: 'revoke', customerId: 'family_42', entId: entitlementId }]);
    assert.deepEqual(result.results, [{ grantId: 7, status: 'synced' }]);
  });

  test('revoke sync (two active grants): calls revokeGrantedEntitlement then grantEntitlement with remaining expiry', async () => {
    const revokeRow = {
      grant_id: '7',
      rc_customer_id: 'family_42',
      action: 'revoke',
      status: 'pending',
      attempts: 0,
      family_id: '42',
      expires_at: null,
      revoked_at: 'now',
    };

    const remainingActiveGrant = {
      id: '5',
      expires_at: '2026-12-31T00:00:00Z',
    };

    let queryIdx = 0;
    const db = mockDb(async (sql) => {
      queryIdx++;
      if (sql.includes('SELECT s.grant_id')) {
        return queryIdx === 2 ? { rows: [revokeRow] } : { rows: [] };
      }
      if (sql.includes('admin_grants') && sql.includes('expires_at')) {
        return { rows: [remainingActiveGrant] };
      }
      return { rows: [] };
    });

    const rcCalls = [];
    const rc = {
      async ensureCustomer() {},
      async grantEntitlement(customerId, entId, expiresAtMs) {
        rcCalls.push({ method: 'grant', customerId, entId, expiresAtMs });
      },
      async revokeGrantedEntitlement(customerId, entId) {
        rcCalls.push({ method: 'revoke', customerId, entId });
      },
    };

    const result = await syncPending(db, rc, { entitlementId, now });
    assert.equal(result.processed, 1);
    assert.deepEqual(result.results, [{ grantId: 7, status: 'synced' }]);
    assert.equal(rcCalls.length, 2);
    assert.deepEqual(rcCalls[0], { method: 'revoke', customerId: 'family_42', entId: entitlementId });
    assert.deepEqual(rcCalls[1], {
      method: 'grant',
      customerId: 'family_42',
      entId: entitlementId,
      expiresAtMs: new Date('2026-12-31T00:00:00Z').getTime(),
    });
  });

  test('revoke sync: 404 from RevenueCat counts as synced', async () => {
    const revokeRow = {
      grant_id: '7',
      rc_customer_id: 'family_42',
      action: 'revoke',
      status: 'pending',
      attempts: 0,
      family_id: '42',
      expires_at: null,
      revoked_at: 'now',
    };

    let queryIdx = 0;
    const db = mockDb(async (sql) => {
      queryIdx++;
      if (sql.includes('SELECT s.grant_id')) {
        return queryIdx === 2 ? { rows: [revokeRow] } : { rows: [] };
      }
      if (sql.includes('SELECT id, expires_at FROM admin_grants')) {
        return { rows: [] };
      }
      return { rows: [] };
    });

    const rc = {
      async ensureCustomer() {},
      async grantEntitlement() {},
      async revokeGrantedEntitlement() {
        throw new RevenueCatError({
          message: 'Customer not found in RevenueCat',
          kind: 'rejected',
          status: 404,
        });
      },
    };

    const result = await syncPending(db, rc, { entitlementId, now });
    assert.equal(result.processed, 1);
    assert.deepEqual(result.results, [{ grantId: 7, status: 'synced' }]);
  });

  test('error handling: unavailable keeps status pending and increments attempts', async () => {
    const row = {
      grant_id: '8',
      rc_customer_id: 'family_42',
      action: 'grant',
      status: 'pending',
      attempts: 2,
      family_id: '42',
      expires_at: null,
      revoked_at: null,
    };

    const queries = [];
    let queryIdx = 0;
    const db = mockDb(async (sql, params) => {
      queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      queryIdx++;
      if (sql.includes('SELECT s.grant_id')) {
        return queryIdx === 2 ? { rows: [row] } : { rows: [] };
      }
      return { rows: [] };
    });

    const rc = {
      async ensureCustomer() {
        throw new RevenueCatError({
          message: 'Rate limit reached',
          kind: 'unavailable',
          status: 429,
        });
      },
    };

    const result = await syncPending(db, rc, { entitlementId, now });
    assert.equal(result.processed, 1);
    assert.deepEqual(result.results, [{ grantId: 8, status: 'pending', attempts: 3 }]);

    const updateCall = queries.find((q) => q.sql.includes('UPDATE admin_rc_sync'));
    assert.ok(updateCall.sql.includes("status = 'pending'"));
    assert.ok(updateCall.sql.includes('attempts = attempts + 1'));
  });

  test('error handling: rejected sets status failed and records sanitized error without client apiKey getter', async () => {
    const row = {
      grant_id: '9',
      rc_customer_id: 'family_42',
      action: 'grant',
      status: 'pending',
      attempts: 0,
      family_id: '42',
      expires_at: null,
      revoked_at: null,
    };

    const queries = [];
    let queryIdx = 0;
    const db = mockDb(async (sql, params) => {
      queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      queryIdx++;
      if (sql.includes('SELECT s.grant_id')) {
        return queryIdx === 2 ? { rows: [row] } : { rows: [] };
      }
      return { rows: [] };
    });

    const rc = {
      // Notice: rc does NOT have an apiKey property
      async ensureCustomer() {
        throw new RevenueCatError({
          message: 'Entitlement not found in project [REDACTED]',
          kind: 'rejected',
          status: 400,
        });
      },
    };

    const result = await syncPending(db, rc, { entitlementId, now });
    assert.equal(result.processed, 1);
    assert.equal(result.results[0].status, 'failed');
    assert.equal(result.results[0].attempts, 1);
    assert.equal(result.results[0].lastError, 'Entitlement not found in project [REDACTED]');

    const updateCall = queries.find((q) => q.sql.includes('UPDATE admin_rc_sync'));
    assert.ok(updateCall.sql.includes("status = 'failed'"));
    assert.equal(updateCall.params[0], 'Entitlement not found in project [REDACTED]');
  });

  test('grantId option targets specific row directly', async () => {
    const queries = [];
    const db = mockDb(async (sql, params) => {
      queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      if (sql.includes('SELECT s.grant_id')) {
        return {
          rows: [
            {
              grant_id: '42',
              rc_customer_id: 'family_10',
              action: 'revoke',
              status: 'failed',
              attempts: 3,
              family_id: '10',
            },
          ],
        };
      }
      return { rows: [] };
    });

    const rc = {
      async revokeGrantedEntitlement() {},
    };

    await syncPending(db, rc, { entitlementId, now, grantId: 42 });
    assert.ok(queries[1].sql.includes('WHERE s.grant_id = $1'));
    assert.equal(queries[1].params[0], 42);
  });
});
