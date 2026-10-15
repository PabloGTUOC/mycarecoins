import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { pool } from '../src/db/pool.js';
import {
  heartbeatBucket, listFamilies, getFamilyRegistry, requestInactivityNotice,
} from '../src/services/adminService.js';
import {
  touchFamilyHeartbeat, familyHeartbeat, clearHeartbeatThrottle,
} from '../src/middleware/heartbeat.js';

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

const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = Date.parse('2026-07-31T12:00:00Z');
const daysAgo = (d) => new Date(NOW - d * DAY_MS).toISOString();

// ─── heartbeatBucket ────────────────────────────────────────────────────────

describe('heartbeatBucket', () => {
  test('classifies by age with 30/90-day boundaries', () => {
    assert.equal(heartbeatBucket(daysAgo(0), NOW), 'active');
    assert.equal(heartbeatBucket(daysAgo(29), NOW), 'active');
    assert.equal(heartbeatBucket(daysAgo(31), NOW), 'dormant');
    assert.equal(heartbeatBucket(daysAgo(89), NOW), 'dormant');
    assert.equal(heartbeatBucket(daysAgo(91), NOW), 'inactive');
    assert.equal(heartbeatBucket(null, NOW), 'inactive');
  });
});

// ─── touchFamilyHeartbeat ───────────────────────────────────────────────────

describe('touchFamilyHeartbeat', () => {
  beforeEach(clearHeartbeatThrottle);

  test('writes once per family per hour', () => {
    const calls = [];
    const query = async (sql, params) => { calls.push(params); };
    let now = NOW;
    assert.equal(touchFamilyHeartbeat(7, { now: () => now, query }), true);
    now += 30 * 60 * 1000; // +30 min — throttled
    assert.equal(touchFamilyHeartbeat(7, { now: () => now, query }), false);
    now += 31 * 60 * 1000; // +61 min total — fires again
    assert.equal(touchFamilyHeartbeat(7, { now: () => now, query }), true);
    assert.deepEqual(calls, [[7], [7]]);
  });

  test('throttles per family, not globally', () => {
    const query = async () => {};
    assert.equal(touchFamilyHeartbeat(1, { now: () => NOW, query }), true);
    assert.equal(touchFamilyHeartbeat(2, { now: () => NOW, query }), true);
  });

  test('ignores invalid ids', () => {
    const query = async () => { throw new Error('should not be called'); };
    assert.equal(touchFamilyHeartbeat('abc', { query }), false);
    assert.equal(touchFamilyHeartbeat(-1, { query }), false);
    assert.equal(touchFamilyHeartbeat(null, { query }), false);
  });
});

// ─── familyHeartbeat middleware ─────────────────────────────────────────────

describe('familyHeartbeat middleware', () => {
  const realQuery = pool.query;
  let touched;
  beforeEach(() => {
    clearHeartbeatThrottle();
    touched = [];
    pool.query = async (sql, params) => { touched.push(params); };
  });
  afterEach(() => { pool.query = realQuery; });

  function simulate({ statusCode, params, query, body }) {
    const req = { params, query, body };
    const res = new EventEmitter();
    res.statusCode = statusCode;
    return new Promise((resolve) => {
      familyHeartbeat(req, res, () => {
        res.emit('finish');
        setImmediate(resolve); // let the fire-and-forget touch run
      });
    });
  }

  test('touches on success using route params', async () => {
    await simulate({ statusCode: 200, params: { familyId: '5' } });
    assert.deepEqual(touched, [[5]]);
  });

  test('falls back to query-string familyId', async () => {
    await simulate({ statusCode: 200, query: { familyId: '9' } });
    assert.deepEqual(touched, [[9]]);
  });

  test('does not touch on error responses', async () => {
    await simulate({ statusCode: 403, params: { familyId: '5' } });
    assert.deepEqual(touched, []);
  });

  test('does not touch when no familyId is present', async () => {
    await simulate({ statusCode: 200, query: {} });
    assert.deepEqual(touched, []);
  });
});

// ─── registry: listFamilies ─────────────────────────────────────────────────

const REGISTRY_KEYS = ['createdAt', 'id', 'lastActiveAt', 'memberCount', 'name', 'planCode', 'status', 'subscriptionStatus'];

describe('listFamilies', () => {
  test('maps rows to allowlisted registry fields only', async () => {
    // Simulate a sloppy future query leaking member identities and content:
    // the explicit mapping must drop every unexpected field.
    const client = mockClient([ok([{
      id: '3', name: 'Casa', created_at: daysAgo(200), last_active_at: daysAgo(2),
      member_count: '4', total: '1',
      email: 'leak@test.com', display_name: 'Leaky', alias: 'leak', title: 'Walk the dog',
    }])]);
    const result = await listFamilies(client, {}, NOW);
    const fam = result.data.families[0];
    assert.deepEqual(Object.keys(fam).sort(), REGISTRY_KEYS);
    assert.equal(fam.memberCount, 4);
    assert.equal(fam.status, 'active');
    assert.equal(result.data.total, 1);
  });

  test('applies search and status filters with pagination', async () => {
    const client = mockClient([ok([])]);
    await listFamilies(client, { search: 'casa', status: 'dormant', page: 2, pageSize: 10 }, NOW);
    const call = client._calls[0];
    assert.ok(call.sql.includes('ILIKE'));
    assert.ok(call.sql.includes(`INTERVAL '90 days'`));
    assert.deepEqual(call.params, ['%casa%', 'casa', 10, 10]);
  });

  test('caps pageSize at 100 and floors page at 1', async () => {
    const client = mockClient([ok([])]);
    await listFamilies(client, { page: 0, pageSize: 5000 }, NOW);
    assert.deepEqual(client._calls[0].params, [100, 0]);
  });
});

// ─── registry: getFamilyRegistry ────────────────────────────────────────────

describe('getFamilyRegistry', () => {
  test('returns 404 for unknown family', async () => {
    const client = mockClient([empty()]);
    const result = await getFamilyRegistry(client, 99, NOW);
    assert.equal(result.error.code, 404);
  });

  test('returns registry fields plus counts, nothing else', async () => {
    const client = mockClient([ok([{
      id: '3', name: 'Casa', created_at: daysAgo(300), last_active_at: daysAgo(40),
      member_count: '2', pending_member_count: '1', actor_count: '1',
      email: 'leak@test.com',
    }])]);
    const result = await getFamilyRegistry(client, 3, NOW);
    assert.deepEqual(Object.keys(result.data).sort(),
      [...REGISTRY_KEYS, 'actorCount', 'pendingMemberCount'].sort());
    assert.equal(result.data.status, 'dormant');
    assert.equal(result.data.pendingMemberCount, 1);
  });
});

// ─── requestInactivityNotice ────────────────────────────────────────────────

describe('requestInactivityNotice', () => {
  const familyRow = {
    id: '3', name: 'Casa', created_at: daysAgo(300), last_active_at: daysAgo(100),
    member_count: '2', pending_member_count: '0', actor_count: '0',
  };

  test('queues the notice and audits it in the same transaction', async () => {
    const client = mockClient([ok([familyRow]), empty(), empty()]);
    const result = await requestInactivityNotice(client, 1, 3);
    assert.equal(result.data.familyId, 3);
    const queued = client._calls[1];
    assert.ok(queued.sql.includes('INSERT INTO admin_family_notices'));
    assert.deepEqual(queued.params, [3, 1]);
    const audit = client._calls[2];
    assert.ok(audit.sql.includes('INSERT INTO admin_audit_log'));
    assert.equal(audit.params[0], 1);
    assert.equal(audit.params[1], 'family.notify_inactive');
    assert.equal(audit.params[3], '3');
  });

  test('does not audit when the family is missing', async () => {
    const client = mockClient([empty()]);
    const result = await requestInactivityNotice(client, 1, 99);
    assert.equal(result.error.code, 404);
    assert.equal(client._calls.length, 1);
  });
});
