import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {
  createDeviceKey,
  resolveDeviceKey,
  revokeDeviceKey,
  revokeAllDeviceKeys,
  listDeviceKeys,
  hashDeviceKey,
} from '../src/services/deviceKeyService.js';
import { requireDeviceKey } from '../src/middleware/deviceKey.js';
import { FORBIDDEN_TABLES } from '../scripts/admin-role.js';

function mockClient(responses) {
  let idx = 0;
  const calls = [];
  return {
    async query(sql, params) {
      calls.push({ sql: sql.replace(/\s+/g, ' ').trim().slice(0, 300), params });
      if (idx >= responses.length) {
        throw new Error(`Unexpected extra query #${idx}: ${sql.trim().slice(0, 60)}`);
      }
      const resp = responses[idx++];
      if (resp instanceof Error) throw resp;
      return resp;
    },
    _calls: calls,
  };
}

const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const empty = () => ({ rows: [], rowCount: 0 });

function mockRes() {
  let statusCode = 200;
  let jsonBody = null;
  return {
    status(s) {
      statusCode = s;
      return this;
    },
    json(body) {
      jsonBody = body;
      return this;
    },
    get statusCode() {
      return statusCode;
    },
    get jsonBody() {
      return jsonBody;
    },
  };
}

describe('createDeviceKey', () => {
  test('not a caregiver → deviceKeyCaregiverOnly', async () => {
    const client = mockClient([
      empty(), // assertMemberRole: not active in family
    ]);
    const res = await createDeviceKey(client, 1, { familyId: 10, label: 'Apple Watch' });
    assert.equal(res.error?.code, 403);
    assert.equal(res.error?.key, 'deviceKeyCaregiverOnly');
    assert.equal(res.error?.message, 'Only caregivers can connect a widget or watch.');
  });

  test('member role instead of caregiver → deviceKeyCaregiverOnly', async () => {
    const client = mockClient([
      ok([{ role: 'member' }]), // assertMemberRole fails role level check
    ]);
    const res = await createDeviceKey(client, 1, { familyId: 10, label: 'Apple Watch' });
    assert.equal(res.error?.code, 403);
    assert.equal(res.error?.key, 'deviceKeyCaregiverOnly');
  });

  test('10 existing keys → deviceKeyLimit', async () => {
    const client = mockClient([
      ok([{ role: 'caregiver' }]), // assertMemberRole passes
      ok([{ count: 10 }]),         // 10 non-revoked keys
    ]);
    const res = await createDeviceKey(client, 1, { familyId: 10, label: 'Apple Watch' });
    assert.equal(res.error?.code, 409);
    assert.equal(res.error?.key, 'deviceKeyLimit');
    assert.equal(res.error?.message, 'Too many connected devices. Remove one first.');
    assert.deepEqual(res.error?.params, { max: 10 });
  });

  test('success: key starts with cck_, length >= 40, hash equals sha256(key) and is not key itself', async () => {
    const createdAt = new Date();
    const client = mockClient([
      ok([{ role: 'caregiver' }]), // assertMemberRole
      ok([{ count: 2 }]),          // existing keys
      ok([{ id: 42, created_at: createdAt }]), // INSERT RETURNING
    ]);

    const res = await createDeviceKey(client, 1, { familyId: 10, label: '  My Watch  ' });
    assert.ok(!res.error, `Unexpected error: ${JSON.stringify(res.error)}`);
    assert.equal(res.data.id, 42);
    assert.equal(res.data.label, 'My Watch');
    assert.equal(res.data.familyId, 10);
    assert.equal(res.data.createdAt, createdAt);

    const key = res.data.key;
    assert.ok(key.startsWith('cck_'), 'Key should start with cck_');
    assert.ok(key.length >= 40, `Key length ${key.length} should be >= 40`);

    const insertCall = client._calls[2];
    assert.ok(insertCall.sql.includes('INSERT INTO device_keys'));
    const storedHash = insertCall.params[3];
    const expectedHash = crypto.createHash('sha256').update(key).digest('hex');
    assert.equal(storedHash, expectedHash);
    assert.notEqual(storedHash, key);
  });
});

describe('resolveDeviceKey', () => {
  test('unknown key → deviceKeyInvalid', async () => {
    const client = mockClient([
      empty(), // SELECT ... WHERE key_hash = $1
    ]);
    const res = await resolveDeviceKey(client, 'cck_unknown');
    assert.equal(res.error?.code, 401);
    assert.equal(res.error?.key, 'deviceKeyInvalid');
    assert.equal(res.error?.message, 'This device is no longer connected.');
  });

  test('revoked key → deviceKeyRevoked', async () => {
    const client = mockClient([
      ok([{
        id: 1,
        user_id: 100,
        family_id: 200,
        revoked_at: new Date(),
        firebase_uid: 'fb_1',
        is_deleted: false,
        role: 'caregiver',
        status: 'active',
      }]),
    ]);
    const res = await resolveDeviceKey(client, 'cck_revoked');
    assert.equal(res.error?.code, 401);
    assert.equal(res.error?.key, 'deviceKeyRevoked');
    assert.equal(res.error?.message, 'This device was disconnected.');
  });

  test('membership status other than active → deviceKeyCaregiverOnly', async () => {
    const client = mockClient([
      ok([{
        id: 1,
        user_id: 100,
        family_id: 200,
        revoked_at: null,
        firebase_uid: 'fb_1',
        is_deleted: false,
        role: 'caregiver',
        status: 'pending',
      }]),
    ]);
    const res = await resolveDeviceKey(client, 'cck_pending');
    assert.equal(res.error?.code, 403);
    assert.equal(res.error?.key, 'deviceKeyCaregiverOnly');
  });

  test('role member → deviceKeyCaregiverOnly', async () => {
    const client = mockClient([
      ok([{
        id: 1,
        user_id: 100,
        family_id: 200,
        revoked_at: null,
        firebase_uid: 'fb_1',
        is_deleted: false,
        role: 'member',
        status: 'active',
      }]),
    ]);
    const res = await resolveDeviceKey(client, 'cck_member');
    assert.equal(res.error?.code, 403);
    assert.equal(res.error?.key, 'deviceKeyCaregiverOnly');
  });

  test('user is_deleted → deviceKeyCaregiverOnly', async () => {
    const client = mockClient([
      ok([{
        id: 1,
        user_id: 100,
        family_id: 200,
        revoked_at: null,
        firebase_uid: 'fb_1',
        is_deleted: true,
        role: 'caregiver',
        status: 'active',
      }]),
    ]);
    const res = await resolveDeviceKey(client, 'cck_deleted_user');
    assert.equal(res.error?.code, 403);
    assert.equal(res.error?.key, 'deviceKeyCaregiverOnly');
  });

  test('success → updates last_used_at and returns firebaseUid', async () => {
    const client = mockClient([
      ok([{
        id: 7,
        user_id: 100,
        family_id: 200,
        revoked_at: null,
        firebase_uid: 'firebase_user_777',
        is_deleted: false,
        role: 'caregiver',
        status: 'active',
      }]),
      ok([], 1), // UPDATE device_keys SET last_used_at = NOW() WHERE id = $1
    ]);

    const res = await resolveDeviceKey(client, 'cck_valid_key');
    assert.ok(!res.error);
    assert.deepEqual(res.data, {
      deviceKeyId: 7,
      userId: 100,
      familyId: 200,
      firebaseUid: 'firebase_user_777',
    });

    const updateCall = client._calls[1];
    assert.ok(updateCall.sql.includes('UPDATE device_keys SET last_used_at'));
    assert.deepEqual(updateCall.params, [7]);
  });
});

describe('revokeDeviceKey', () => {
  test('on someone else\'s key or already revoked → deviceKeyNotFound', async () => {
    const client = mockClient([
      empty(), // UPDATE rowCount: 0
    ]);
    const res = await revokeDeviceKey(client, 1, 999);
    assert.equal(res.error?.code, 404);
    assert.equal(res.error?.key, 'deviceKeyNotFound');
    assert.equal(res.error?.message, 'Device not found.');
  });

  test('success → marks revoked_at and returns success', async () => {
    const client = mockClient([
      ok([{ id: 5 }], 1),
    ]);
    const res = await revokeDeviceKey(client, 1, 5);
    assert.ok(!res.error);
    assert.deepEqual(res.data, { success: true });
    assert.deepEqual(client._calls[0].params, [5, 1]);
  });
});

describe('revokeAllDeviceKeys', () => {
  test('revokes all keys of user', async () => {
    const client = mockClient([
      ok([], 3),
    ]);
    const res = await revokeAllDeviceKeys(client, 42);
    assert.ok(!res.error);
    assert.deepEqual(res.data, { success: true });
    assert.deepEqual(client._calls[0].params, [42]);
  });
});

describe('listDeviceKeys', () => {
  test('returns non-revoked keys without hash', async () => {
    const row = {
      id: 1,
      label: 'iPhone Widget',
      family_id: 10,
      created_at: new Date(),
      last_used_at: null,
    };
    const client = mockClient([
      ok([row]),
    ]);
    const res = await listDeviceKeys(client, 5);
    assert.ok(!res.error);
    assert.deepEqual(res.data, [row]);
    assert.equal(res.data[0].key_hash, undefined);
  });
});

describe('requireDeviceKey', () => {
  test('missing header → 401 deviceKeyInvalid and next not called', async () => {
    const req = { headers: {} };
    const res = mockRes();
    let nextCalled = false;

    await requireDeviceKey(req, res, () => { nextCalled = true; });

    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 401);
    assert.equal(res.jsonBody?.code, 'deviceKeyInvalid');
  });

  test('Bearer token header → 401 deviceKeyInvalid and next not called', async () => {
    const req = { headers: { authorization: 'Bearer some_token' } };
    const res = mockRes();
    let nextCalled = false;

    await requireDeviceKey(req, res, () => { nextCalled = true; });

    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 401);
    assert.equal(res.jsonBody?.code, 'deviceKeyInvalid');
  });

  test('happy path with stubbed client → sets req.auth and req.device and calls next', async () => {
    const client = mockClient([
      ok([{
        id: 12,
        user_id: 34,
        family_id: 56,
        revoked_at: null,
        firebase_uid: 'fb_uid_123',
        is_deleted: false,
        role: 'caregiver',
        status: 'active',
      }]),
      ok([], 1),
    ]);

    const req = {
      headers: { authorization: 'Device cck_valid_token' },
      _withTransaction: async (cb) => cb(client),
    };
    const res = mockRes();
    let nextCalled = false;

    await requireDeviceKey(req, res, () => { nextCalled = true; });

    assert.equal(nextCalled, true);
    assert.deepEqual(req.auth, { uid: 'fb_uid_123', email: null, name: null, authTime: null });
    assert.deepEqual(req.device, { id: 12, userId: 34, familyId: 56 });
  });

  test('database error → 500 internal', async () => {
    const req = {
      headers: { authorization: 'Device cck_valid_token' },
      _withTransaction: async () => { throw new Error('DB connection failed'); },
    };
    const res = mockRes();
    let nextCalled = false;

    await requireDeviceKey(req, res, () => { nextCalled = true; });

    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 500);
    assert.equal(res.jsonBody?.code, 'internal');
  });
});

describe('admin-role.js', () => {
  test('FORBIDDEN_TABLES includes device_keys', () => {
    assert.ok(FORBIDDEN_TABLES.includes('device_keys'), 'FORBIDDEN_TABLES must contain device_keys');
  });
});
