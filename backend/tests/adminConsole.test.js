import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import request from 'supertest';
import { SignJWT, generateKeyPair, exportJWK, createLocalJWKSet } from 'jose';
import { createAdminApp, createOperatorLimiter } from '../src/admin/app.js';
import { createAccessVerifier, accessVerifierFromEnv, requireAccess } from '../src/admin/access.js';
import { requireOperator, requireRecentSignIn, RECENT_SIGN_IN_SECONDS } from '../src/admin/operator.js';
import { deliverPendingNotices, NOTICE_MESSAGES } from '../src/services/noticeOutbox.js';
import { adminRouter } from '../src/routes/admin.js';
import { GRANT_STATEMENTS, FORBIDDEN_TABLES } from '../scripts/admin-role.js';
import { AppStoreError } from '../src/admin/appstore.js';
import { RevenueCatError } from '../src/admin/revenuecat.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const TEAM = 'https://carecoins.cloudflareaccess.com';
const AUD = 'aud-tag-123';
const NOW = Date.parse('2026-10-15T12:00:00Z');

async function accessKeys() {
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = { ...(await exportJWK(publicKey)), kid: 'k1', alg: 'RS256' };
  const keys = createLocalJWKSet({ keys: [jwk] });
  const sign = (claims = {}, { issuer = TEAM, audience = AUD } = {}) =>
    new SignJWT({ email: 'owner@example.com', ...claims })
      .setProtectedHeader({ alg: 'RS256', kid: 'k1' })
      .setIssuer(issuer)
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime('5m')
      .sign(privateKey);
  return { keys, sign };
}

// A db whose admin_operators lookup answers from a list of firebase uids.
function operatorsDb(adminUids) {
  return {
    async query(sql, params) {
      if (sql.includes('admin_operators')) {
        return adminUids.includes(params[0]) ? { rows: [{ id: '7' }] } : { rows: [] };
      }
      throw new Error(`Unexpected query: ${sql.slice(0, 60)}`);
    },
  };
}

const fakeAuth = (uid, authTime) => (req, _res, next) => {
  req.auth = { uid, email: null, name: null, authTime };
  next();
};

// ─── Cloudflare Access ───────────────────────────────────────────────────────

describe('Cloudflare Access verifier', () => {
  test('accepts a token signed for this team and application', async () => {
    const { keys, sign } = await accessKeys();
    const verify = createAccessVerifier({ teamDomain: TEAM, audience: AUD, keys });
    const payload = await verify(await sign());
    assert.equal(payload.email, 'owner@example.com');
  });

  test('rejects another application (wrong audience)', async () => {
    const { keys, sign } = await accessKeys();
    const verify = createAccessVerifier({ teamDomain: TEAM, audience: AUD, keys });
    await assert.rejects(verify(await sign({}, { audience: 'other-app' })));
  });

  test('rejects another team (wrong issuer)', async () => {
    const { keys, sign } = await accessKeys();
    const verify = createAccessVerifier({ teamDomain: TEAM, audience: AUD, keys });
    await assert.rejects(verify(await sign({}, { issuer: 'https://evil.cloudflareaccess.com' })));
  });

  test('production refuses to run without Access settings', () => {
    assert.throws(() => accessVerifierFromEnv({ NODE_ENV: 'production' }));
    assert.equal(accessVerifierFromEnv({ NODE_ENV: 'development' }), null);
    assert.equal(typeof accessVerifierFromEnv({ CF_ACCESS_TEAM_DOMAIN: TEAM, CF_ACCESS_AUD: AUD }), 'function');
  });

  test('middleware: missing header is 403 accessMissing, bad token 403 accessInvalid', async () => {
    const verify = async (t) => { if (t !== 'good') throw new Error('bad'); return { email: 'a@b.c' }; };
    const app = createAdminApp({ db: operatorsDb(['uid-admin']), verifyAccess: verify,
      authenticate: fakeAuth('uid-admin', NOW / 1000), now: () => NOW });

    const missing = await request(app).get('/admin-api/status');
    assert.equal(missing.status, 403);
    assert.equal(missing.body.code, 'accessMissing');

    const bad = await request(app).get('/admin-api/status').set('Cf-Access-Jwt-Assertion', 'nope');
    assert.equal(bad.status, 403);
    assert.equal(bad.body.code, 'accessInvalid');

    const good = await request(app).get('/admin-api/status').set('Cf-Access-Jwt-Assertion', 'good');
    assert.equal(good.status, 200);
  });

  test('without a verifier (local work) the check is skipped', async () => {
    let called = false;
    await requireAccess(null)({ headers: {} }, {}, () => { called = true; });
    assert.ok(called);
  });
});

// ─── Operator and recent sign-in ─────────────────────────────────────────────

describe('requireOperator', () => {
  test('an operator passes and gets adminUser from admin_operators', async () => {
    const app = createAdminApp({ db: operatorsDb(['uid-admin']),
      authenticate: fakeAuth('uid-admin', NOW / 1000), now: () => NOW });
    const res = await request(app).get('/admin-api/status');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { ok: true, adminId: 7 });
  });

  test('anyone else is 403 adminOnly, without touching users', async () => {
    const app = createAdminApp({ db: operatorsDb(['uid-admin']),
      authenticate: fakeAuth('uid-someone', NOW / 1000), now: () => NOW });
    const res = await request(app).get('/admin-api/status');
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'adminOnly');
  });

  test('a failing lookup is a 500, not a pass', async () => {
    const db = { query: async () => { throw new Error('down'); } };
    let passed = false;
    const res = { status(c) { this.c = c; return this; }, json(b) { this.b = b; return this; } };
    await requireOperator(db)({ auth: { uid: 'x' } }, res, () => { passed = true; });
    assert.equal(passed, false);
    assert.equal(res.c, 500);
  });
});

describe('requireRecentSignIn', () => {
  const stale = NOW / 1000 - RECENT_SIGN_IN_SECONDS - 1;
  const fresh = NOW / 1000 - 60;

  test('reads pass with an old sign-in', async () => {
    const app = createAdminApp({ db: operatorsDb(['uid-admin']),
      authenticate: fakeAuth('uid-admin', stale), now: () => NOW });
    assert.equal((await request(app).get('/admin-api/status')).status, 200);
  });

  test('changes with an old sign-in are 401 adminReauthRequired', async () => {
    const app = createAdminApp({ db: operatorsDb(['uid-admin']),
      authenticate: fakeAuth('uid-admin', stale), now: () => NOW });
    const res = await request(app).post('/admin-api/plans').send({ code: 'x', name: 'X' });
    assert.equal(res.status, 401);
    assert.equal(res.body.code, 'adminReauthRequired');
    assert.deepEqual(res.body.params, { maxAgeMinutes: 30 });
  });

  test('changes with a fresh sign-in reach the route', () => {
    let passed = false;
    requireRecentSignIn(undefined, () => NOW)(
      { method: 'POST', auth: { authTime: fresh } }, {}, () => { passed = true; });
    assert.ok(passed);
  });

  test('a token without auth_time cannot make changes', () => {
    let passed = false;
    const res = { status(c) { this.c = c; return this; }, json() { return this; } };
    requireRecentSignIn(undefined, () => NOW)({ method: 'DELETE', auth: {} }, res, () => { passed = true; });
    assert.equal(passed, false);
    assert.equal(res.c, 401);
  });
});

// ─── Rate limiter ────────────────────────────────────────────────────────────

describe('operatorLimiter', () => {
  test('returns 429 with code rateLimited when rate limit exceeded', async () => {
    const app = createAdminApp({
      db: operatorsDb(['uid-admin']),
      authenticate: fakeAuth('uid-admin', NOW / 1000),
      now: () => NOW,
      operatorLimiter: createOperatorLimiter({ max: 1 }),
    });

    const first = await request(app).get('/admin-api/status');
    assert.equal(first.status, 200);

    const second = await request(app).get('/admin-api/status');
    assert.equal(second.status, 429);
    assert.equal(second.body.code, 'rateLimited');
    assert.equal(second.body.error, 'Too many requests. Please try again later.');
  });
});

// ─── Separation from the public API ──────────────────────────────────────────

describe('separation', () => {
  test('the public app never imports the operator console', () => {
    const files = [];
    const walk = (dir) => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) { if (e.name !== 'admin') walk(full); }
        else if (e.name.endsWith('.js')) files.push(full);
      }
    };
    walk(path.resolve(__dirname, '../src'));
    const offenders = files.filter((f) => /from\s+['"][^'"]*\/admin\/[^'"]*['"]/.test(fs.readFileSync(f, 'utf8')));
    assert.deepEqual(offenders.map((f) => path.relative(path.resolve(__dirname, '..'), f)), []);
  });

  test('the console only answers under /admin-api', async () => {
    const app = createAdminApp({ db: operatorsDb(['uid-admin']),
      authenticate: fakeAuth('uid-admin', NOW / 1000), now: () => NOW });
    assert.equal((await request(app).get('/api/me')).status, 404);
    assert.equal((await request(app).get('/api/families')).status, 404);
  });
});

// ─── Database role grants (static) ───────────────────────────────────────────

describe('carecoins_admin grants', () => {
  test('no grant names a content table', () => {
    const granted = GRANT_STATEMENTS.join('\n');
    const leaks = FORBIDDEN_TABLES.filter((t) => new RegExp(`\\b${t}\\b`).test(granted));
    assert.deepEqual(leaks, []);
  });

  test('billing_events is granted without its payload column', () => {
    const line = GRANT_STATEMENTS.find((s) => s.includes('billing_events'));
    assert.ok(line.includes('SELECT ('));
    assert.ok(!line.includes('payload'));
  });
});

// ─── Notice outbox ───────────────────────────────────────────────────────────

describe('deliverPendingNotices', () => {
  test('claims queued notices and pushes each to the family caregivers', async () => {
    const queries = [];
    const db = {
      async query(sql, params) {
        queries.push({ sql, params });
        return { rows: [{ id: '1', family_id: '3', kind: 'inactive' }, { id: '2', family_id: '9', kind: 'inactive' }] };
      },
    };
    const sent = [];
    const count = await deliverPendingNotices(db, async (familyId, exclude, message) => {
      sent.push({ familyId, exclude, message });
    });
    assert.equal(count, 2);
    assert.ok(queries[0].sql.includes('FOR UPDATE SKIP LOCKED'));
    assert.deepEqual(sent.map((s) => s.familyId), [3, 9]);
    assert.equal(sent[0].exclude, 0);
    assert.deepEqual(sent[0].message, NOTICE_MESSAGES.inactive);
  });

  test('an unknown kind is claimed but not sent', async () => {
    const db = { query: async () => ({ rows: [{ id: '1', family_id: '3', kind: 'mystery' }] }) };
    let calls = 0;
    const count = await deliverPendingNotices(db, async () => { calls++; });
    assert.equal(count, 0);
    assert.equal(calls, 0);
  });

  test('nothing queued sends nothing', async () => {
    const db = { query: async () => ({ rows: [] }) };
    assert.equal(await deliverPendingNotices(db, async () => { throw new Error('no'); }), 0);
  });
});

// ─── POST /admin-api/families/:familyId/grants/:grantId/rc-sync ───────────────

describe('POST /admin-api/families/:familyId/grants/:grantId/rc-sync', () => {
  const stale = NOW / 1000 - RECENT_SIGN_IN_SECONDS - 1;
  const fresh = NOW / 1000 - 60;

  function mockConsoleDb({ grantExists = true, syncExists = true, updatedRow = null } = {}) {
    const queries = [];
    return {
      _queries: queries,
      async connect() {
        return {
          async query(sql, params) {
            queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
            if (sql.includes('admin_operators')) {
              return { rows: [{ id: '7' }] };
            }
            if (sql.includes('BEGIN') || sql.includes('COMMIT') || sql.includes('ROLLBACK')) {
              return { rows: [] };
            }
            if (sql.includes('SELECT id FROM admin_grants')) {
              return grantExists ? { rows: [{ id: 1 }] } : { rows: [] };
            }
            if (sql.includes('UPDATE admin_rc_sync')) {
              return syncExists
                ? { rows: [{ status: 'pending', attempts: 0, last_error: null, synced_at: null }], rowCount: 1 }
                : { rows: [], rowCount: 0 };
            }
            if (sql.includes('INSERT INTO admin_audit_log')) {
              return { rows: [] };
            }
            if (sql.includes('SELECT status, attempts, last_error, synced_at FROM admin_rc_sync')) {
              return { rows: [updatedRow ?? { status: 'synced', attempts: 0, last_error: null, synced_at: 'now' }] };
            }
            return { rows: [] };
          },
          release() {},
        };
      },
      async query(sql, params) {
        queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
        if (sql.includes('admin_operators')) {
          return { rows: [{ id: '7' }] };
        }
        return { rows: [] };
      },
    };
  }

  test('requires recent sign-in (401 adminReauthRequired when stale)', async () => {
    const db = mockConsoleDb();
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', stale),
      now: () => NOW,
    });
    const res = await request(app).post('/admin-api/families/42/grants/5/rc-sync');
    assert.equal(res.status, 401);
    assert.equal(res.body.code, 'adminReauthRequired');
  });

  test('returns 404 notFound when grant does not belong to family', async () => {
    const db = mockConsoleDb({ grantExists: false });
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
    });
    const res = await request(app).post('/admin-api/families/42/grants/999/rc-sync');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
  });

  test('returns 404 notFound when grant has no admin_rc_sync row (pre-phase grant)', async () => {
    const db = mockConsoleDb({ grantExists: true, syncExists: false });
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
    });
    const res = await request(app).post('/admin-api/families/42/grants/5/rc-sync');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
    assert.equal(res.body.error, 'Grant has no RevenueCat sync record.');
  });

  test('with mirror off: sets row to pending, audits, returns mirror off', async () => {
    const db = mockConsoleDb({ grantExists: true });
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rcConfig: null,
      rc: null,
    });
    const res = await request(app).post('/admin-api/families/42/grants/5/rc-sync');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { status: 'pending', mirror: 'off' });

    const auditCall = db._queries.find((q) => q.sql.includes('INSERT INTO admin_audit_log'));
    assert.ok(auditCall);
    assert.equal(auditCall.params[1], 'grant.rc_retry');
  });

  test('with mirror on: runs syncPending for that row and returns updated status', async () => {
    const db = mockConsoleDb({
      grantExists: true,
      updatedRow: { status: 'synced', attempts: 0, last_error: null, synced_at: 'now' },
    });

    const fakeRc = {
      async ensureCustomer() {},
      async grantEntitlement() {},
      async revokeGrantedEntitlement() {},
    };

    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: fakeRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_pro' },
    });

    const res = await request(app).post('/admin-api/families/42/grants/5/rc-sync');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'synced');
  });

  test('returns 500 internal when syncPending throws an unexpected error', async () => {
    const db = {
      async connect() {
        return {
          async query(sql) {
            if (sql.includes('admin_operators')) return { rows: [{ id: '7' }] };
            if (sql.includes('BEGIN') || sql.includes('COMMIT') || sql.includes('ROLLBACK')) return { rows: [] };
            if (sql.includes('SELECT id FROM admin_grants')) return { rows: [{ id: 1 }] };
            if (sql.includes('UPDATE admin_rc_sync')) {
              return { rows: [{ status: 'pending', attempts: 0, last_error: null, synced_at: null }], rowCount: 1 };
            }
            if (sql.includes('INSERT INTO admin_audit_log')) return { rows: [] };
            if (sql.includes('SELECT s.grant_id')) {
              throw new Error('Database disk full');
            }
            return { rows: [] };
          },
          release() {},
        };
      },
      async query(sql) {
        if (sql.includes('admin_operators')) return { rows: [{ id: '7' }] };
        return { rows: [] };
      },
    };

    const fakeRc = {
      async ensureCustomer() {},
      async grantEntitlement() {},
      async revokeGrantedEntitlement() {},
    };

    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: fakeRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_pro' },
    });

    const res = await request(app).post('/admin-api/families/42/grants/5/rc-sync');
    assert.equal(res.status, 500);
    assert.equal(res.body.code, 'internal');
    assert.equal(res.body.error, 'Failed to retry sync.');
    assert.equal(res.body.lastError, undefined); // Never leak raw message
  });

  test('does not exist on the public /api/admin', () => {
    // Assert route is not mounted in adminRouter (the router mounted by public app.js)
    const hasRoute = adminRouter.stack.some(
      (layer) => layer.route?.path === '/families/:familyId/grants/:grantId/rc-sync'
    );
    assert.equal(hasRoute, false);
  });
});

// ─── App Store Endpoints ──────────────────────────────────────────────────────

describe('GET /admin-api/appstore/catalog', () => {
  const fresh = NOW / 1000 - 60;

  function mockDb() {
    const queries = [];
    return {
      _queries: queries,
      async query(sql, params) {
        queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
        if (sql.includes('admin_operators')) return { rows: [{ id: '7' }] };
        return { rows: [] };
      },
    };
  }

  test('returns 503 appStoreNotConfigured when App Store client is not configured', async () => {
    const db = mockDb();
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      appStore: null,
      appStoreConfig: null,
    });

    const res = await request(app).get('/admin-api/appstore/catalog');
    assert.equal(res.status, 503);
    assert.equal(res.body.code, 'appStoreNotConfigured');
  });

  test('returns 200 with catalog and caches in memory for 10 minutes', async () => {
    const db = mockDb();
    let getCatalogCalls = 0;
    const fakeCatalog = {
      app: { id: 'app_1', name: 'MyCareCoins', bundleId: 'app.mycarecoins' },
      subscriptionGroups: [
        {
          id: 'g_1',
          referenceName: 'Pro',
          subscriptions: [
            {
              id: 's_1',
              name: 'Monthly',
              productId: 'pro_monthly',
              state: 'APPROVED',
              prices: [{ territory: 'USA', customerPrice: '4.99', currency: 'USD', startDate: null }],
            },
          ],
        },
      ],
    };

    const fakeAppStore = {
      connect: {
        async getCatalog() {
          getCatalogCalls++;
          return fakeCatalog;
        },
      },
    };

    let currentNow = NOW;
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => currentNow,
      appStore: fakeAppStore,
      appStoreConfig: { connect: { keyId: 'k', issuerId: 'i', privateKey: 'p' } },
    });

    // First call: fetches catalog
    const res1 = await request(app).get('/admin-api/appstore/catalog');
    assert.equal(res1.status, 200);
    assert.deepEqual(res1.body, fakeCatalog);
    assert.equal(getCatalogCalls, 1);

    // Second call 5 minutes later: served from cache
    currentNow += 5 * 60 * 1000;
    const res2 = await request(app).get('/admin-api/appstore/catalog');
    assert.equal(res2.status, 200);
    assert.deepEqual(res2.body, fakeCatalog);
    assert.equal(getCatalogCalls, 1);

    // Third call with ?refresh=1: bypasses cache and re-fetches
    const res3 = await request(app).get('/admin-api/appstore/catalog?refresh=1');
    assert.equal(res3.status, 200);
    assert.deepEqual(res3.body, fakeCatalog);
    assert.equal(getCatalogCalls, 2);
  });

  test('maps AppStoreError to 502 appStoreUnavailable or appStoreRejected', async () => {
    const db = mockDb();
    const unavailableAppStore = {
      connect: {
        async getCatalog() {
          throw new AppStoreError({ message: 'Rate limited by Apple', kind: 'unavailable', status: 429 });
        },
      },
    };

    const app1 = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      appStore: unavailableAppStore,
      appStoreConfig: { connect: { keyId: 'k', issuerId: 'i', privateKey: 'p' } },
    });

    const res1 = await request(app1).get('/admin-api/appstore/catalog');
    assert.equal(res1.status, 502);
    assert.equal(res1.body.code, 'appStoreUnavailable');

    const rejectedAppStore = {
      connect: {
        async getCatalog() {
          throw new AppStoreError({ message: 'Invalid credentials', kind: 'rejected', status: 401 });
        },
      },
    };

    const app2 = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      appStore: rejectedAppStore,
      appStoreConfig: { connect: { keyId: 'k', issuerId: 'i', privateKey: 'p' } },
    });

    const res2 = await request(app2).get('/admin-api/appstore/catalog');
    assert.equal(res2.status, 502);
    assert.equal(res2.body.code, 'appStoreRejected');
  });

  test('does not exist on the public /api/admin', () => {
    const hasRoute = adminRouter.stack.some(
      (layer) => layer.route?.path === '/appstore/catalog'
    );
    assert.equal(hasRoute, false);
  });
});

describe('GET /admin-api/appstore/transactions/:transactionId', () => {
  const fresh = NOW / 1000 - 60;

  function mockDb() {
    const queries = [];
    return {
      _queries: queries,
      async query(sql, params) {
        queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
        if (sql.includes('admin_operators')) return { rows: [{ id: '7' }] };
        if (sql.includes('INSERT INTO admin_audit_log')) return { rows: [] };
        return { rows: [] };
      },
    };
  }

  test('validates transactionId: returns 400 invalidInput when not digits or >20 chars', async () => {
    const db = mockDb();
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
    });

    const res1 = await request(app).get('/admin-api/appstore/transactions/not-digits');
    assert.equal(res1.status, 400);
    assert.equal(res1.body.code, 'invalidInput');

    const res2 = await request(app).get('/admin-api/appstore/transactions/1234567890123456789012345');
    assert.equal(res2.status, 400);
    assert.equal(res2.body.code, 'invalidInput');
  });

  test('returns 503 appStoreNotConfigured when server API client is not configured', async () => {
    const db = mockDb();
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      appStore: null,
      appStoreConfig: null,
    });

    const res = await request(app).get('/admin-api/appstore/transactions/1000000123');
    assert.equal(res.status, 503);
    assert.equal(res.body.code, 'appStoreNotConfigured');
  });

  test('returns 404 notFound when transaction is not found in Apple', async () => {
    const db = mockDb();
    const fakeAppStore = {
      server: {
        async lookupTransaction() {
          throw new AppStoreError({ message: 'Transaction id not found.', kind: 'rejected', status: 404 });
        },
      },
    };

    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      appStore: fakeAppStore,
      appStoreConfig: { server: { keyId: 'k', issuerId: 'i', bundleId: 'b', privateKey: 'p' } },
    });

    const res = await request(app).get('/admin-api/appstore/transactions/999999999');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
  });

  test('returns 200 with transaction data and writes admin_audit_log on success', async () => {
    const db = mockDb();
    const fakeData = {
      productId: 'pro_monthly',
      transactionId: '1000000123',
      originalTransactionId: '1000000123',
      purchaseDate: '2024-01-01T00:00:00.000Z',
      expiresDate: '2024-02-01T00:00:00.000Z',
      environment: 'Production',
      type: 'Auto-Renewable Subscription',
      inAppOwnershipType: 'PURCHASED',
      revocationDate: null,
      revocationReason: null,
      autoRenewStatus: 1,
      autoRenewProductId: 'pro_monthly',
      expirationIntent: null,
      status: 1,
    };

    let passedEnv = null;
    const fakeAppStore = {
      server: {
        async lookupTransaction(id, { environment }) {
          passedEnv = environment;
          return fakeData;
        },
      },
    };

    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      appStore: fakeAppStore,
      appStoreConfig: { server: { keyId: 'k', issuerId: 'i', bundleId: 'b', privateKey: 'p' } },
    });

    const res = await request(app).get('/admin-api/appstore/transactions/1000000123?environment=sandbox');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, fakeData);
    assert.equal(passedEnv, 'sandbox');

    // Audit log written
    const auditQuery = db._queries.find((q) => q.sql.includes('INSERT INTO admin_audit_log'));
    assert.ok(auditQuery);
    assert.equal(auditQuery.params[0], 7); // admin id
    assert.equal(auditQuery.params[1], 'appstore.transaction_lookup');
    assert.equal(auditQuery.params[2], 'transaction');
    assert.equal(auditQuery.params[3], '1000000123');
    assert.deepEqual(JSON.parse(auditQuery.params[4]), { transactionId: '1000000123', environment: 'sandbox' });
  });

  test('does not exist on the public /api/admin', () => {
    const hasRoute = adminRouter.stack.some(
      (layer) => layer.route?.path === '/appstore/transactions/:transactionId'
    );
    assert.equal(hasRoute, false);
  });
});

describe('GET /admin-api/overview', () => {
  const fresh = NOW / 1000 - 60;

  function mockDb() {
    const queries = [];
    return {
      _queries: queries,
      async query(sql, params) {
        queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
        if (sql.includes('admin_operators')) return { rows: [{ id: '7' }] };
        if (sql.includes('COUNT(*) FILTER (WHERE f.last_active_at > NOW()')) {
          return {
            rows: [{ total: 50, active: 30, dormant: 15, inactive: 5 }],
          };
        }
        if (sql.includes("'plan' AS dimension")) {
          return {
            rows: [
              { dimension: 'plan', key: 'free', count: 40 },
              { dimension: 'plan', key: 'pro', count: 10 },
              { dimension: 'status', key: 'active', count: 48 },
              { dimension: 'status', key: 'canceled', count: 2 },
              { dimension: 'store', key: 'app_store', count: 8 },
              { dimension: 'store', key: 'play_store', count: 2 },
              { dimension: 'store', key: 'none', count: 40 },
            ],
          };
        }
        if (sql.includes('FROM admin_grants')) {
          return {
            rows: [{ active_grants: 4, families_count: 3 }],
          };
        }
        if (sql.includes('FROM admin_rc_sync')) {
          return {
            rows: [{ pending: 1, synced: 10, failed: 2, oldest_pending_minutes: 15.6 }],
          };
        }
        if (sql.includes('MAX(created_at) AS last_event_at')) {
          return {
            rows: [
              {
                last_event_at: '2026-10-16T12:00:00.000Z',
                events_last_30_days: 120,
                unattributed_last_30_days: 3,
                unprocessed_last_30_days: 1,
              },
            ],
          };
        }
        if (sql.includes('family_id IS NULL OR processed = false')) {
          return {
            rows: [
              { id: '101', event_type: 'INITIAL_PURCHASE', created_at: '2026-10-16T11:00:00.000Z' },
            ],
          };
        }
        return { rows: [] };
      },
    };
  }

  test('returns 200 with all overview figures and revenueCat metrics when configured', async () => {
    const db = mockDb();
    const fakeMetrics = [
      { id: 'overview/mrr', name: 'MRR', value: 12450.5, unit: 'USD', period: 'P0D' },
      { id: 'overview/active_subscriptions', name: 'Active Subscriptions', value: 850, unit: null, period: 'P0D' },
    ];
    let metricsCallCount = 0;
    const fakeRc = {
      async getMetricsOverview() {
        metricsCallCount++;
        return fakeMetrics;
      },
    };

    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: fakeRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'e' },
    });

    const res = await request(app).get('/admin-api/overview');
    assert.equal(res.status, 200);

    // Families
    assert.equal(res.body.families.total, 50);
    assert.deepEqual(res.body.families.byHeartbeat, { active: 30, dormant: 15, inactive: 5 });
    assert.deepEqual(res.body.families.byPlan, { free: 40, pro: 10 });
    assert.deepEqual(res.body.families.byStatus, { active: 48, canceled: 2 });
    assert.deepEqual(res.body.families.byStore, { app_store: 8, play_store: 2, none: 40 });

    // Free plans
    assert.deepEqual(res.body.freePlans, { activeGrants: 4, familiesCount: 3 });

    // Mirror
    assert.deepEqual(res.body.mirror, {
      mirror: 'on',
      pending: 1,
      synced: 10,
      failed: 2,
      oldestPendingAgeMinutes: 15,
    });

    // Webhooks
    assert.equal(res.body.webhooks.lastEventAt, '2026-10-16T12:00:00.000Z');
    assert.equal(res.body.webhooks.eventsLast30Days, 120);
    assert.equal(res.body.webhooks.unattributedLast30Days, 3);
    assert.equal(res.body.webhooks.unprocessedLast30Days, 1);
    assert.deepEqual(res.body.webhooks.recentEvents, [
      { id: 101, eventType: 'INITIAL_PURCHASE', createdAt: '2026-10-16T11:00:00.000Z' },
    ]);

    // RevenueCat
    assert.deepEqual(res.body.revenueCat, { metrics: fakeMetrics });
    assert.equal(metricsCallCount, 1);
  });

  test('caches revenueCat metrics for 10 minutes and supports ?refresh=1 bypass', async () => {
    const db = mockDb();
    let metricsCallCount = 0;
    const fakeRc = {
      async getMetricsOverview() {
        metricsCallCount++;
        return [{ id: 'mrr', name: 'MRR', value: 100, unit: 'USD', period: 'P0D' }];
      },
    };

    let currentNow = NOW;
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => currentNow,
      rc: fakeRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'e' },
    });

    // Call 1: fetches from RC
    const res1 = await request(app).get('/admin-api/overview');
    assert.equal(res1.status, 200);
    assert.equal(metricsCallCount, 1);

    // Call 2: after 5 minutes, uses in-memory cache
    currentNow = NOW + 5 * 60 * 1000;
    const res2 = await request(app).get('/admin-api/overview');
    assert.equal(res2.status, 200);
    assert.equal(metricsCallCount, 1);

    // Call 3: with ?refresh=1, bypasses cache
    const res3 = await request(app).get('/admin-api/overview?refresh=1');
    assert.equal(res3.status, 200);
    assert.equal(metricsCallCount, 2);
  });

  test('returns revenueCat: null when mirror is off', async () => {
    const db = mockDb();
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: null,
      rcConfig: null,
    });

    const res = await request(app).get('/admin-api/overview');
    assert.equal(res.status, 200);
    assert.equal(res.body.revenueCat, null);
    assert.equal(res.body.mirror.mirror, 'off');
    assert.equal(res.body.families.total, 50);
  });

  test('returns revenueCat: { error: "unavailable" } when RevenueCat fails, leaving all other figures intact', async () => {
    const db = mockDb();
    const fakeRc = {
      async getMetricsOverview() {
        throw new RevenueCatError({ message: 'RC down', kind: 'unavailable', status: 500 });
      },
    };

    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: fakeRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'e' },
    });

    const res = await request(app).get('/admin-api/overview');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.revenueCat, { error: 'unavailable' });
    assert.equal(res.body.families.total, 50);
    assert.equal(res.body.freePlans.activeGrants, 4);
  });

  test('does not exist on the public /api/admin', () => {
    const hasRoute = adminRouter.stack.some(
      (layer) => layer.route?.path === '/overview'
    );
    assert.equal(hasRoute, false);
  });
});

describe('GET /admin-api/families/:familyId/revenuecat', () => {
  const fresh = NOW / 1000 - 60;

  function mockFamilyDb({ familyExists = true, plan = null, grants = [] } = {}) {
    return {
      async query(sql, params) {
        if (sql.includes('admin_operators')) return { rows: [{ id: '7' }] };
        if (sql.includes('admin_family_registry')) {
          return { rows: familyExists ? [{ id: params[0] }] : [] };
        }
        if (sql.includes('family_plans')) {
          return { rows: plan ? [plan] : [] };
        }
        if (sql.includes('admin_grants')) {
          return { rows: grants };
        }
        return { rows: [] };
      },
    };
  }

  test('returns 200 with both customers and active entitlements when mirror is on', async () => {
    const db = mockFamilyDb({
      plan: { plan_code: 'pro', status: 'active', provider: 'revenuecat', billing_owner_user_id: 10 },
      grants: [{ id: 1, plan_code: 'free', sync_status: 'synced' }],
    });

    const fakeRc = {
      async getCustomer(id) {
        if (id === 'family_1') {
          return {
            id: 'family_1',
            active_entitlements: {
              items: [{ entitlement_id: 'ent_free', expires_at: NOW + 30 * 24 * 60 * 60 * 1000, store: 'promotional', grant_type: 'free' }],
            },
            last_seen_at: NOW - 1000,
          };
        }
        if (id === '10') {
          return {
            id: '10',
            active_entitlements: {
              items: [{ entitlement_id: 'ent_free', expires_at: NOW + 30 * 24 * 60 * 60 * 1000, store: 'app_store' }],
            },
            last_seen_at: NOW - 1000,
          };
        }
        throw new RevenueCatError({ kind: 'rejected', status: 404, message: 'Not found' });
      },
    };

    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: fakeRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
    });

    const res = await request(app).get('/admin-api/families/1/revenuecat');
    assert.equal(res.status, 200);
    assert.equal(res.body.familyCustomer.customerId, 'family_1');
    assert.equal(res.body.familyCustomer.found, true);
    assert.equal(res.body.familyCustomer.entitlements.length, 1);
    assert.equal(res.body.familyCustomer.entitlements[0].id, 'ent_free');
    assert.equal(res.body.familyCustomer.entitlements[0].store, 'promotional');
    assert.equal(res.body.familyCustomer.entitlements[0].grantType, 'free');
    assert.equal(res.body.billingOwnerCustomer.customerId, '10');
    assert.equal(res.body.billingOwnerCustomer.found, true);
    assert.equal(res.body.billingOwnerCustomer.entitlements.length, 1);
    assert.deepEqual(res.body.mismatches, []);
  });

  test('returns 404 notFound when family does not exist in registry', async () => {
    const db = mockFamilyDb({ familyExists: false });
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: { async getCustomer() {} },
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
    });

    const res = await request(app).get('/admin-api/families/999/revenuecat');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
  });

  test('returns 503 revenueCatNotConfigured when mirror config is off', async () => {
    const db = mockFamilyDb();
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: null,
      rcConfig: null,
    });

    const res = await request(app).get('/admin-api/families/1/revenuecat');
    assert.equal(res.status, 503);
    assert.equal(res.body.code, 'revenueCatNotConfigured');
  });

  test('handles RevenueCat 404 as found: false without error', async () => {
    const db = mockFamilyDb({
      plan: { plan_code: 'pro', status: 'canceled', provider: 'stripe', billing_owner_user_id: null },
      grants: [],
    });

    const fakeRc = {
      async getCustomer() {
        throw new RevenueCatError({ kind: 'rejected', status: 404, message: 'Customer not found' });
      },
    };

    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: fakeRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
    });

    const res = await request(app).get('/admin-api/families/1/revenuecat');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.familyCustomer, {
      customerId: 'family_1',
      found: false,
      entitlements: [],
      lastSeenAt: null,
    });
    assert.equal(res.body.billingOwnerCustomer, null);
    assert.deepEqual(res.body.mismatches, []);
  });

  test('returns 502 revenueCatUnavailable / revenueCatRejected on RevenueCat error', async () => {
    const db = mockFamilyDb();

    // Unavailable
    const unavailableRc = {
      async getCustomer() {
        throw new RevenueCatError({ kind: 'unavailable', status: 503, message: 'RC unavailable' });
      },
    };
    const app1 = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: unavailableRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
    });
    const res1 = await request(app1).get('/admin-api/families/1/revenuecat');
    assert.equal(res1.status, 502);
    assert.equal(res1.body.code, 'revenueCatUnavailable');

    // Rejected
    const rejectedRc = {
      async getCustomer() {
        throw new RevenueCatError({ kind: 'rejected', status: 401, message: 'Invalid credentials' });
      },
    };
    const app2 = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => NOW,
      rc: rejectedRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
    });
    const res2 = await request(app2).get('/admin-api/families/1/revenuecat');
    assert.equal(res2.status, 502);
    assert.equal(res2.body.code, 'revenueCatRejected');
  });

  test('caches result for 60 seconds and supports ?refresh=1 bypass', async () => {
    const db = mockFamilyDb({
      plan: null,
      grants: [],
    });

    let callCount = 0;
    const fakeRc = {
      async getCustomer(id) {
        callCount++;
        return { id, active_entitlements: { items: [] } };
      },
    };

    let currentNow = NOW;
    const app = createAdminApp({
      db,
      authenticate: fakeAuth('uid-admin', fresh),
      now: () => currentNow,
      rc: fakeRc,
      rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
    });

    // 1st call: queries RC
    const res1 = await request(app).get('/admin-api/families/1/revenuecat');
    assert.equal(res1.status, 200);
    assert.equal(callCount, 1);

    // 2nd call at +30s: hits cache
    currentNow = NOW + 30 * 1000;
    const res2 = await request(app).get('/admin-api/families/1/revenuecat');
    assert.equal(res2.status, 200);
    assert.equal(callCount, 1);

    // 3rd call at +70s: cache expired, queries RC
    currentNow = NOW + 70 * 1000;
    const res3 = await request(app).get('/admin-api/families/1/revenuecat');
    assert.equal(res3.status, 200);
    assert.equal(callCount, 2);

    // 4th call at +75s with ?refresh=1: bypasses cache
    currentNow = NOW + 75 * 1000;
    const res4 = await request(app).get('/admin-api/families/1/revenuecat?refresh=1');
    assert.equal(res4.status, 200);
    assert.equal(callCount, 3);
  });

  test('identifies all 4 mismatch conditions', async () => {
    // 1. freePlanNotMirrored: DB has active synced grant, but family customer has no active RC entitlement
    {
      const db = mockFamilyDb({
        grants: [{ id: 1, plan_code: 'free', sync_status: 'synced' }],
      });
      const rc = {
        async getCustomer() {
          return { active_entitlements: { items: [] } };
        },
      };
      const app = createAdminApp({
        db,
        authenticate: fakeAuth('uid-admin', fresh),
        now: () => NOW,
        rc,
        rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
      });
      const res = await request(app).get('/admin-api/families/1/revenuecat');
      assert.equal(res.status, 200);
      assert.equal(res.body.mismatches.some((m) => m.code === 'freePlanNotMirrored'), true);
    }

    // 2. mirrorStale: DB has no active grant, but family customer has active RC entitlement
    {
      const db = mockFamilyDb({ grants: [] });
      const rc = {
        async getCustomer() {
          return {
            active_entitlements: {
              items: [{ entitlement_id: 'ent_free', expires_at: NOW + 100000 }],
            },
          };
        },
      };
      const app = createAdminApp({
        db,
        authenticate: fakeAuth('uid-admin', fresh),
        now: () => NOW,
        rc,
        rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
      });
      const res = await request(app).get('/admin-api/families/1/revenuecat');
      assert.equal(res.status, 200);
      assert.equal(res.body.mismatches.some((m) => m.code === 'mirrorStale'), true);
    }

    // 3. subscriptionMissingInRevenueCat: DB has active RC subscription, but billing owner has no entitlement
    {
      const db = mockFamilyDb({
        plan: { plan_code: 'pro', status: 'active', provider: 'revenuecat', billing_owner_user_id: 10 },
      });
      const rc = {
        async getCustomer() {
          return { active_entitlements: { items: [] } };
        },
      };
      const app = createAdminApp({
        db,
        authenticate: fakeAuth('uid-admin', fresh),
        now: () => NOW,
        rc,
        rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
      });
      const res = await request(app).get('/admin-api/families/1/revenuecat');
      assert.equal(res.status, 200);
      assert.equal(res.body.mismatches.some((m) => m.code === 'subscriptionMissingInRevenueCat'), true);
    }

    // 4. subscriptionMissingHere: billing owner has active entitlement, but DB is not active RC sub
    {
      const db = mockFamilyDb({
        plan: { plan_code: 'pro', status: 'canceled', provider: 'revenuecat', billing_owner_user_id: 10 },
      });
      const rc = {
        async getCustomer(id) {
          if (id === '10') {
            return {
              active_entitlements: {
                items: [{ entitlement_id: 'ent_free', expires_at: NOW + 100000 }],
              },
            };
          }
          return { active_entitlements: { items: [] } };
        },
      };
      const app = createAdminApp({
        db,
        authenticate: fakeAuth('uid-admin', fresh),
        now: () => NOW,
        rc,
        rcConfig: { apiKey: 'k', projectId: 'p', entitlementId: 'ent_free' },
      });
      const res = await request(app).get('/admin-api/families/1/revenuecat');
      assert.equal(res.status, 200);
      assert.equal(res.body.mismatches.some((m) => m.code === 'subscriptionMissingHere'), true);
    }
  });

  test('does not exist on the public /api/admin', () => {
    const hasRoute = adminRouter.stack.some(
      (layer) => layer.route?.path === '/families/:familyId/revenuecat'
    );
    assert.equal(hasRoute, false);
  });
});

