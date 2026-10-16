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
import { GRANT_STATEMENTS, FORBIDDEN_TABLES } from '../scripts/admin-role.js';

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
