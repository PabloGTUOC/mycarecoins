import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import express from 'express';
import { createInternalRouter, createInternalLimiter } from '../src/routes/internal.js';
import { reprocessEvent } from '../src/services/billingService.js';
import app from '../src/app.js';

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

describe('reprocessEvent service', () => {
  test('reprocess applies a stored INITIAL_PURCHASE when no newer processed events exist', async () => {
    const client = mockClient([
      ok([{
        id: 1,
        event_id: 'evt_1',
        event_type: 'INITIAL_PURCHASE',
        family_id: 7,
        payload: { ...baseEvent, event_timestamp_ms: 1000 },
        processed: false,
      }]),
      ok([]), // no newer processed events
      conflict(), // INSERT INTO plans ON CONFLICT DO NOTHING
      inserted(), // INSERT INTO family_plans ... ON CONFLICT DO UPDATE
      inserted(), // UPDATE billing_events SET processed = true, family_id = ...
    ]);

    const result = await reprocessEvent(client, 1);
    assert.deepEqual(result.data, { processed: true, outcome: 'applied' });

    assert.equal(client._calls.length, 5);
    assert.ok(client._calls[0].sql.includes('SELECT id, event_id'));
    assert.ok(client._calls[0].sql.includes('FOR UPDATE'));
    assert.equal(client._calls[0].params[0], 1);

    assert.ok(client._calls[1].sql.includes("payload->>'event_timestamp_ms'"));
    assert.equal(client._calls[1].params[0], 7);
    assert.equal(client._calls[1].params[1], 1000);

    const upsert = client._calls[3];
    assert.ok(upsert.sql.includes('INSERT INTO family_plans'));
    assert.equal(upsert.params[0], 7);
    assert.equal(upsert.params[1], 'pro');
    assert.equal(upsert.params[2], 'active');

    assert.ok(client._calls[4].sql.includes('UPDATE billing_events SET processed = true'));
  });

  test('already-processed event returns 409 reprocessAlreadyProcessed', async () => {
    const client = mockClient([
      ok([{
        id: 1,
        event_id: 'evt_1',
        event_type: 'INITIAL_PURCHASE',
        family_id: 7,
        payload: baseEvent,
        processed: true,
      }]),
    ]);

    const result = await reprocessEvent(client, 1);
    assert.equal(result.error.code, 409);
    assert.equal(result.error.key, 'reprocessAlreadyProcessed');
    assert.equal(result.error.message, 'This event was already applied.');
    assert.equal(client._calls.length, 1);
    assert.ok(!client._calls.some((c) => c.sql.includes('family_plans')));
  });

  test('older unprocessed purchase after a processed newer expiration returns stale and leaves family_plans untouched', async () => {
    const oldPurchaseEvent = {
      ...baseEvent,
      id: 'evt_old_purchase',
      type: 'INITIAL_PURCHASE',
      event_timestamp_ms: 1000,
      subscriber_attributes: { family_id: { value: '7' } },
    };

    const client = mockClient([
      ok([{
        id: 1,
        event_id: 'evt_old_purchase',
        event_type: 'INITIAL_PURCHASE',
        family_id: 7,
        payload: oldPurchaseEvent,
        processed: false,
      }]),
      // Processed newer EXPIRATION event exists in billing_events (e.g. at timestamp 2000)
      ok([{ id: 99 }]),
      inserted(), // UPDATE billing_events SET processed = true, family_id = ...
    ]);

    const result = await reprocessEvent(client, 1);
    assert.deepEqual(result.data, { processed: true, outcome: 'stale' });

    assert.equal(client._calls.length, 3);
    assert.ok(client._calls[0].sql.includes('SELECT id, event_id'));
    assert.ok(client._calls[0].sql.includes('FOR UPDATE'));

    assert.ok(client._calls[1].sql.includes("payload->>'event_timestamp_ms'"));
    assert.equal(client._calls[1].params[0], 7);
    assert.equal(client._calls[1].params[1], 1000);

    assert.ok(client._calls[2].sql.includes('UPDATE billing_events SET processed = true'));
    assert.equal(client._calls[2].params[0], 1);
    assert.equal(client._calls[2].params[1], 7);

    // family_plans is completely untouched
    assert.ok(!client._calls.some((c) => c.sql.includes('family_plans')));
  });

  test('a newer unprocessed event still applies when processed event is older', async () => {
    const newPurchaseEvent = {
      ...baseEvent,
      id: 'evt_new_purchase',
      type: 'INITIAL_PURCHASE',
      event_timestamp_ms: 3000,
      subscriber_attributes: { family_id: { value: '7' } },
    };

    const client = mockClient([
      ok([{
        id: 1,
        event_id: 'evt_new_purchase',
        event_type: 'INITIAL_PURCHASE',
        family_id: 7,
        payload: newPurchaseEvent,
        processed: false,
      }]),
      ok([]), // no newer processed events
      conflict(),
      inserted(),
      inserted(),
    ]);

    const result = await reprocessEvent(client, 1);
    assert.deepEqual(result.data, { processed: true, outcome: 'applied' });
    assert.equal(client._calls.length, 5);

    const upsert = client._calls[3];
    assert.ok(upsert.sql.includes('INSERT INTO family_plans'));
    assert.equal(upsert.params[0], 7);
    assert.equal(upsert.params[1], 'pro');
    assert.equal(upsert.params[2], 'active');
  });

  test('stale check falls back to created_at when payload has no event_timestamp_ms', async () => {
    const createdAt = new Date('2026-10-10T00:00:00Z');
    const noTimestampEvent = {
      ...baseEvent,
      id: 'evt_no_ts',
      subscriber_attributes: { family_id: { value: '7' } },
    };
    delete noTimestampEvent.event_timestamp_ms;

    const client = mockClient([
      ok([{
        id: 1,
        event_id: 'evt_no_ts',
        event_type: 'INITIAL_PURCHASE',
        family_id: 7,
        payload: noTimestampEvent,
        processed: false,
        created_at: createdAt,
      }]),
      ok([{ id: 88 }]), // Newer event found by created_at
      inserted(),
    ]);

    const result = await reprocessEvent(client, 1);
    assert.deepEqual(result.data, { processed: true, outcome: 'stale' });

    assert.ok(client._calls[1].sql.includes('created_at > $2'));
    assert.equal(client._calls[1].params[0], 7);
    assert.equal(client._calls[1].params[1], createdAt);
    assert.ok(!client._calls.some((c) => c.sql.includes('family_plans')));
  });

  test('PROMOTIONAL stays a no-op and marks processed', async () => {
    const client = mockClient([
      ok([{
        id: 2,
        event_id: 'evt_promo',
        event_type: 'INITIAL_PURCHASE',
        family_id: null,
        payload: { ...baseEvent, id: 'evt_promo', store: 'PROMOTIONAL' },
        processed: false,
      }]),
      ok([]), // no newer events
      inserted(), // UPDATE billing_events SET processed = true
    ]);

    const result = await reprocessEvent(client, 2);
    assert.deepEqual(result.data, { processed: true, outcome: 'promotional_mirror' });
    assert.equal(client._calls.length, 3);
    assert.ok(client._calls[2].sql.includes('UPDATE billing_events SET processed = true'));
    assert.ok(!client._calls.some((c) => c.sql.includes('family_plans')));
  });

  test('unattributed event stays unattributed unless payload has attribution', async () => {
    const client = mockClient([
      ok([{
        id: 3,
        event_id: 'evt_unatt',
        event_type: 'INITIAL_PURCHASE',
        family_id: null,
        payload: { ...baseEvent, id: 'evt_unatt', subscriber_attributes: {} },
        processed: false,
      }]),
    ]);

    const result = await reprocessEvent(client, 3);
    assert.deepEqual(result.data, { processed: false, outcome: 'unattributed' });
    assert.equal(client._calls.length, 1);
    assert.ok(!client._calls.some((c) => c.sql.includes('family_plans')));
  });

  test('unknown id → 404 notFound', async () => {
    const client = mockClient([ok([])]);
    const result = await reprocessEvent(client, 999);
    assert.equal(result.error.code, 404);
    assert.equal(result.error.key, 'notFound');
  });

  test('invalid id → 400 invalidInput', async () => {
    const client = mockClient([]);
    const result = await reprocessEvent(client, 'invalid');
    assert.equal(result.error.code, 400);
    assert.equal(result.error.key, 'invalidInput');
  });
});

describe('POST /internal/billing-events/:id/reprocess router', () => {
  const TEST_TOKEN = 'test-secret-token-1234567890';

  function createTestInternalApp({
    token = TEST_TOKEN,
    clientResponses = [],
    limiter = null,
  } = {}) {
    const app = express();
    app.use(express.json());
    const client = mockClient(clientResponses);
    const router = createInternalRouter({
      token,
      limiter,
      runTransaction: async (cb) => cb(client),
    });
    app.use('/internal', router);
    return { app, client };
  }

  test('token unset → 404 notFound', async () => {
    const { app: testApp } = createTestInternalApp({ token: null });
    const res = await request(testApp)
      .post('/internal/billing-events/1/reprocess')
      .set('X-Internal-Token', TEST_TOKEN);
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
  });

  test('token missing → 404 notFound', async () => {
    const { app: testApp } = createTestInternalApp();
    const res = await request(testApp).post('/internal/billing-events/1/reprocess');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
  });

  test('token wrong (different content) → 404 notFound', async () => {
    const { app: testApp } = createTestInternalApp();
    const res = await request(testApp)
      .post('/internal/billing-events/1/reprocess')
      .set('X-Internal-Token', 'wrong-secret-token-1234567890');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
  });

  test('token wrong (different length) → 404 notFound', async () => {
    const { app: testApp } = createTestInternalApp();
    const res = await request(testApp)
      .post('/internal/billing-events/1/reprocess')
      .set('X-Internal-Token', 'short');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
  });

  test('token valid: successfully reprocesses event', async () => {
    const { app: testApp } = createTestInternalApp({
      clientResponses: [
        ok([{
          id: 1,
          event_id: 'evt_1',
          event_type: 'INITIAL_PURCHASE',
          family_id: 7,
          payload: baseEvent,
          processed: false,
        }]),
        ok([]),
        conflict(),
        inserted(),
        inserted(),
      ],
    });

    const res = await request(testApp)
      .post('/internal/billing-events/1/reprocess')
      .set('X-Internal-Token', TEST_TOKEN);

    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { processed: true, outcome: 'applied' });
  });

  test('token valid: already-processed event returns 409 reprocessAlreadyProcessed', async () => {
    const { app: testApp } = createTestInternalApp({
      clientResponses: [
        ok([{
          id: 1,
          event_id: 'evt_1',
          event_type: 'INITIAL_PURCHASE',
          family_id: 7,
          payload: baseEvent,
          processed: true,
        }]),
      ],
    });

    const res = await request(testApp)
      .post('/internal/billing-events/1/reprocess')
      .set('X-Internal-Token', TEST_TOKEN);

    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'reprocessAlreadyProcessed');
    assert.equal(res.body.error, 'This event was already applied.');
  });

  test('token valid: older unprocessed purchase returns outcome stale', async () => {
    const { app: testApp } = createTestInternalApp({
      clientResponses: [
        ok([{
          id: 1,
          event_id: 'evt_1',
          event_type: 'INITIAL_PURCHASE',
          family_id: 7,
          payload: { ...baseEvent, event_timestamp_ms: 1000 },
          processed: false,
        }]),
        ok([{ id: 99 }]),
        inserted(),
      ],
    });

    const res = await request(testApp)
      .post('/internal/billing-events/1/reprocess')
      .set('X-Internal-Token', TEST_TOKEN);

    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { processed: true, outcome: 'stale' });
  });

  test('token valid: unknown event id returns 404 notFound', async () => {
    const { app: testApp } = createTestInternalApp({
      clientResponses: [ok([])],
    });

    const res = await request(testApp)
      .post('/internal/billing-events/999/reprocess')
      .set('X-Internal-Token', TEST_TOKEN);

    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'notFound');
  });

  test('rate limiter returns 429 rateLimited when budget exceeded', async () => {
    const { app: testApp } = createTestInternalApp({
      limiter: createInternalLimiter({ max: 1 }),
      clientResponses: [
        ok([{
          id: 1,
          event_id: 'evt_1',
          event_type: 'INITIAL_PURCHASE',
          family_id: 7,
          payload: baseEvent,
          processed: false,
        }]),
        ok([]),
        conflict(),
        inserted(),
        inserted(),
      ],
    });

    const first = await request(testApp)
      .post('/internal/billing-events/1/reprocess')
      .set('X-Internal-Token', TEST_TOKEN);
    assert.equal(first.status, 200);

    const second = await request(testApp)
      .post('/internal/billing-events/1/reprocess')
      .set('X-Internal-Token', TEST_TOKEN);
    assert.equal(second.status, 429);
    assert.equal(second.body.code, 'rateLimited');
  });
});
