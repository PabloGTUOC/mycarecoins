import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createRevenueCatClient,
  RevenueCatError,
  revenueCatConfigFromEnv,
} from '../src/admin/revenuecat.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function loadFixture(name) {
  const file = path.join(__dirname, 'fixtures', 'revenuecat', name);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function fakeFetch(handler) {
  const calls = [];
  const fn = async (url, options = {}) => {
    calls.push({ url, ...options });
    return handler(url, options);
  };
  fn._calls = calls;
  return fn;
}

const jsonResponse = (data, status = 200) => ({
  ok: status >= 200 && status < 300,
  status,
  async text() {
    return JSON.stringify(data);
  },
});

describe('revenueCatConfigFromEnv', () => {
  test('returns config when all 3 keys are present', () => {
    const config = revenueCatConfigFromEnv({
      RC_SECRET_API_KEY: 'sec_123',
      RC_PROJECT_ID: 'proj_456',
      RC_ENTITLEMENT_ID: 'ent_pro',
    });
    assert.deepEqual(config, {
      apiKey: 'sec_123',
      projectId: 'proj_456',
      entitlementId: 'ent_pro',
    });
  });

  test('returns null when any key is missing or blank', () => {
    assert.equal(revenueCatConfigFromEnv({}), null);
    assert.equal(revenueCatConfigFromEnv({ RC_SECRET_API_KEY: 'k', RC_PROJECT_ID: 'p' }), null);
    assert.equal(revenueCatConfigFromEnv({ RC_SECRET_API_KEY: '', RC_PROJECT_ID: 'p', RC_ENTITLEMENT_ID: 'e' }), null);
    assert.equal(revenueCatConfigFromEnv({ RC_SECRET_API_KEY: '  ', RC_PROJECT_ID: 'p', RC_ENTITLEMENT_ID: 'e' }), null);
  });
});

describe('createRevenueCatClient', () => {
  const apiKey = 'test_secret_rc_key_999';
  const projectId = 'proj_test_123';

  test('does not expose apiKey or projectId as properties on client', () => {
    const client = createRevenueCatClient({ apiKey, projectId, fetch: async () => {} });
    assert.equal(client.apiKey, undefined);
    assert.equal(client.projectId, undefined);
  });

  test('ensureCustomer creates customer with attributes array', async () => {
    const createdFixture = loadFixture('customer_created.json');
    const fetch = fakeFetch(async (url, opts) => {
      assert.equal(url, 'https://api.revenuecat.com/v2/projects/proj_test_123/customers');
      assert.equal(opts.method, 'POST');
      assert.equal(opts.headers.Authorization, `Bearer ${apiKey}`);
      const body = JSON.parse(opts.body);
      assert.equal(body.id, 'family_42');
      assert.deepEqual(body.attributes, [{ name: 'family_id', value: '42' }]);
      return jsonResponse(createdFixture, 201);
    });

    const client = createRevenueCatClient({ apiKey, projectId, fetch });
    const result = await client.ensureCustomer('family_42', [{ name: 'family_id', value: '42' }]);
    assert.equal(result.id, 'family_42');
    assert.equal(fetch._calls.length, 1);
  });

  test('ensureCustomer handles 409 conflict and sets attributes on existing customer', async () => {
    const conflictFixture = loadFixture('customer_exists_409.json');
    const attrFixture = loadFixture('attributes_updated.json');

    let callCount = 0;
    const fetch = fakeFetch(async (url, opts) => {
      callCount++;
      if (callCount === 1) {
        assert.equal(url, 'https://api.revenuecat.com/v2/projects/proj_test_123/customers');
        return jsonResponse(conflictFixture, 409);
      }
      if (callCount === 2) {
        assert.equal(url, 'https://api.revenuecat.com/v2/projects/proj_test_123/customers/family_42/attributes');
        assert.equal(opts.method, 'POST');
        const body = JSON.parse(opts.body);
        assert.deepEqual(body.attributes, [{ name: 'family_id', value: '42' }]);
        return jsonResponse(attrFixture, 200);
      }
      throw new Error('Unexpected call');
    });

    const client = createRevenueCatClient({ apiKey, projectId, fetch });
    const result = await client.ensureCustomer('family_42', [{ name: 'family_id', value: '42' }]);
    assert.equal(result.id, 'family_42');
    assert.equal(fetch._calls.length, 2);
  });

  test('grantEntitlement calls grant action with entitlementId and expiry', async () => {
    const grantFixture = loadFixture('grant_success.json');
    const fetch = fakeFetch(async (url, opts) => {
      assert.equal(
        url,
        'https://api.revenuecat.com/v2/projects/proj_test_123/customers/family_42/actions/grant_entitlement'
      );
      assert.equal(opts.method, 'POST');
      assert.equal(opts.headers.Authorization, `Bearer ${apiKey}`);
      const body = JSON.parse(opts.body);
      assert.equal(body.entitlement_id, 'ent_pro');
      assert.equal(body.expires_at, 1790000000000);
      return jsonResponse(grantFixture, 200);
    });

    const client = createRevenueCatClient({ apiKey, projectId, fetch });
    const result = await client.grantEntitlement('family_42', 'ent_pro', 1790000000000);
    assert.equal(result.entitlement_id, 'ent_pro');
  });

  test('revokeGrantedEntitlement calls revoke action', async () => {
    const revokeFixture = loadFixture('revoke_success.json');
    const fetch = fakeFetch(async (url, opts) => {
      assert.equal(
        url,
        'https://api.revenuecat.com/v2/projects/proj_test_123/customers/family_42/actions/revoke_granted_entitlement'
      );
      assert.equal(opts.method, 'POST');
      const body = JSON.parse(opts.body);
      assert.equal(body.entitlement_id, 'ent_pro');
      return jsonResponse(revokeFixture, 200);
    });

    const client = createRevenueCatClient({ apiKey, projectId, fetch });
    const result = await client.revokeGrantedEntitlement('family_42', 'ent_pro');
    assert.equal(result.revoked, true);
  });

  test('getCustomer returns customer data', async () => {
    const getFixture = loadFixture('customer_get.json');
    const fetch = fakeFetch(async (url, opts) => {
      assert.equal(url, 'https://api.revenuecat.com/v2/projects/proj_test_123/customers/family_42');
      assert.equal(opts.method, 'GET');
      return jsonResponse(getFixture, 200);
    });

    const client = createRevenueCatClient({ apiKey, projectId, fetch });
    const result = await client.getCustomer('family_42');
    assert.equal(result.id, 'family_42');
  });

  test('maps 429 rate limit to unavailable RevenueCatError', async () => {
    const rateLimitFixture = loadFixture('error_rate_limited.json');
    const fetch = fakeFetch(async () => jsonResponse(rateLimitFixture, 429));
    const client = createRevenueCatClient({ apiKey, projectId, fetch });

    await assert.rejects(
      async () => client.getCustomer('family_42'),
      (err) => {
        assert.ok(err instanceof RevenueCatError);
        assert.equal(err.kind, 'unavailable');
        assert.equal(err.status, 429);
        assert.equal(err.type, 'rate_limit_error');
        assert.match(err.message, /Too many requests/);
        return true;
      }
    );
  });

  test('maps 500 server error to unavailable RevenueCatError', async () => {
    const fetch = fakeFetch(async () => jsonResponse({ message: 'Internal Server Error' }, 500));
    const client = createRevenueCatClient({ apiKey, projectId, fetch });

    await assert.rejects(
      async () => client.getCustomer('family_42'),
      (err) => {
        assert.ok(err instanceof RevenueCatError);
        assert.equal(err.kind, 'unavailable');
        assert.equal(err.status, 500);
        return true;
      }
    );
  });

  test('maps 400/404 client errors to rejected RevenueCatError', async () => {
    const invalidFixture = loadFixture('error_invalid.json');
    const fetch = fakeFetch(async () => jsonResponse(invalidFixture, 400));
    const client = createRevenueCatClient({ apiKey, projectId, fetch });

    await assert.rejects(
      async () => client.grantEntitlement('family_42', 'bad_ent', 1000),
      (err) => {
        assert.ok(err instanceof RevenueCatError);
        assert.equal(err.kind, 'rejected');
        assert.equal(err.status, 400);
        assert.equal(err.type, 'invalid_request_error');
        assert.match(err.message, /not found in project/);
        return true;
      }
    );
  });

  test('maps network errors to unavailable RevenueCatError', async () => {
    const fetch = fakeFetch(async () => {
      throw new Error('fetch failed: ECONNREFUSED');
    });
    const client = createRevenueCatClient({ apiKey, projectId, fetch });

    await assert.rejects(
      async () => client.getCustomer('family_42'),
      (err) => {
        assert.ok(err instanceof RevenueCatError);
        assert.equal(err.kind, 'unavailable');
        assert.equal(err.status, null);
        assert.match(err.message, /ECONNREFUSED/);
        return true;
      }
    );
  });

  test('maps timeout to unavailable RevenueCatError', async () => {
    const fetch = fakeFetch(async (url, opts) => {
      return new Promise((resolve, reject) => {
        opts.signal.addEventListener('abort', () => {
          const abortErr = new Error('The operation was aborted');
          abortErr.name = 'AbortError';
          reject(abortErr);
        });
      });
    });

    const client = createRevenueCatClient({ apiKey, projectId, fetch, timeoutMs: 20 });
    await assert.rejects(
      async () => client.getCustomer('family_42'),
      (err) => {
        assert.ok(err instanceof RevenueCatError);
        assert.equal(err.kind, 'unavailable');
        assert.match(err.message, /timed out/);
        return true;
      }
    );
  });

  test('never leaks apiKey in RevenueCatError message', async () => {
    const leakyMessage = `Error with key ${apiKey} occurred`;
    const fetch = fakeFetch(async () => jsonResponse({ message: leakyMessage }, 400));
    const client = createRevenueCatClient({ apiKey, projectId, fetch });

    await assert.rejects(
      async () => client.getCustomer('family_42'),
      (err) => {
        assert.ok(!err.message.includes(apiKey));
        assert.ok(err.message.includes('[REDACTED]'));
        return true;
      }
    );
  });
});
