import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { processWebhookEvent } from '../src/services/billingService.js';

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
const inserted = () => ({ rows: [], rowCount: 1 });
const conflict = () => ({ rows: [], rowCount: 0 });

const baseEvent = {
  id: 'evt_1',
  type: 'INITIAL_PURCHASE',
  app_user_id: '42',
  store: 'PLAY_STORE',
  entitlement_ids: ['MyCareCoins Pro'],
  original_transaction_id: 'GPA.1234',
  expiration_at_ms: 1790000000000,
  subscriber_attributes: { family_id: { value: '7' } },
};

describe('processWebhookEvent', () => {
  test('initial purchase upserts the family subscription and marks processed', async () => {
    const client = mockClient([inserted(), conflict(), inserted(), inserted()]);
    const result = await processWebhookEvent(client, baseEvent);
    assert.deepEqual(result.data, { familyId: 7, planCode: 'pro', status: 'active' });

    const upsert = client._calls[2];
    assert.ok(upsert.sql.includes('INSERT INTO family_plans'));
    assert.equal(upsert.params[0], 7);            // family
    assert.equal(upsert.params[1], 'pro');        // plan
    assert.equal(upsert.params[2], 'active');     // status
    assert.ok(upsert.params[3] instanceof Date);  // period end
    assert.equal(upsert.params[4], 'play');       // platform
    assert.equal(upsert.params[5], 'GPA.1234');   // provider subscription id
    assert.equal(upsert.params[6], 42);           // billing owner

    assert.ok(client._calls[3].sql.includes('SET processed = true'));
  });

  test('replayed event id is acknowledged without reprocessing', async () => {
    const client = mockClient([conflict()]);
    const result = await processWebhookEvent(client, baseEvent);
    assert.deepEqual(result.data, { duplicate: true });
    assert.equal(client._calls.length, 1);
  });

  test('event without family attribution is logged but not applied', async () => {
    const client = mockClient([inserted()]);
    const result = await processWebhookEvent(client, { ...baseEvent, id: 'evt_2', subscriber_attributes: {} });
    assert.deepEqual(result.data, { unattributed: true });
    assert.equal(client._calls.length, 1);
    assert.equal(client._calls[0].params[2], null); // family_id null in the log
  });

  test('unknown event types are stored and ignored', async () => {
    const client = mockClient([inserted(), inserted()]);
    const result = await processWebhookEvent(client, { ...baseEvent, id: 'evt_3', type: 'TEST' });
    assert.deepEqual(result.data, { ignored: 'TEST' });
  });

  test('lifecycle mapping: cancel keeps record as canceled, expiration expires, lifetime has no period end', async () => {
    for (const [type, expectedStatus] of [
      ['CANCELLATION', 'canceled'],
      ['EXPIRATION', 'expired'],
      ['BILLING_ISSUE', 'in_grace'],
      ['SUBSCRIPTION_PAUSED', 'paused'],
    ]) {
      const client = mockClient([inserted(), conflict(), inserted(), inserted()]);
      await processWebhookEvent(client, { ...baseEvent, id: `evt_${type}`, type });
      assert.equal(client._calls[2].params[2], expectedStatus, type);
    }

    const client = mockClient([inserted(), conflict(), inserted(), inserted()]);
    await processWebhookEvent(client, {
      ...baseEvent, id: 'evt_life', type: 'NON_RENEWING_PURCHASE', expiration_at_ms: undefined,
    });
    assert.equal(client._calls[2].params[2], 'active');
    assert.equal(client._calls[2].params[3], null); // lifetime: no period end
  });

  test('malformed events are rejected', async () => {
    const result = await processWebhookEvent(mockClient([]), { type: 'RENEWAL' });
    assert.equal(result.error.code, 400);
  });

  test('loop guard: PROMOTIONAL store events are marked processed and never touch family_plans or plans', async () => {
    for (const type of ['NON_RENEWING_PURCHASE', 'INITIAL_PURCHASE']) {
      const client = mockClient([inserted(), inserted()]);
      const result = await processWebhookEvent(client, {
        ...baseEvent,
        id: `evt_promo_${type}`,
        type,
        store: 'PROMOTIONAL',
      });
      assert.deepEqual(result.data, { ignored: 'promotional_mirror' });
      assert.equal(client._calls.length, 2);
      assert.ok(client._calls[0].sql.includes('INSERT INTO billing_events'));
      assert.ok(client._calls[1].sql.includes('SET processed = true'));
      assert.ok(!client._calls.some(c => c.sql.includes('family_plans')));
      assert.ok(!client._calls.some(c => c.sql.includes('plans')));
    }

    // Normal APP_STORE event still writes family_plans
    const appStoreClient = mockClient([inserted(), conflict(), inserted(), inserted()]);
    const appStoreResult = await processWebhookEvent(appStoreClient, {
      ...baseEvent,
      id: 'evt_app_store',
      type: 'INITIAL_PURCHASE',
      store: 'APP_STORE',
    });
    assert.deepEqual(appStoreResult.data, { familyId: 7, planCode: 'pro', status: 'active' });
    assert.ok(appStoreClient._calls.some(c => c.sql.includes('INSERT INTO family_plans')));
  });
});
