import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { runAutoCompleteSweep, RUNNING_CAP_MINUTES } from '../src/db/autoComplete.js';

function mockClient(responses) {
  let idx = 0;
  const calls = [];
  return {
    async query(sql, params) {
      calls.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
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

const ok = (rows) => ({ rows, rowCount: rows.length });
const empty = () => ({ rows: [], rowCount: 0 });

describe('autoComplete sweep and running tasks cap', () => {
  test('RUNNING_CAP_MINUTES is exported and equals 240', () => {
    assert.equal(RUNNING_CAP_MINUTES, 240);
  });

  test('cap UPDATE runs first with family_id and 240 as parameters', async () => {
    const client = mockClient([
      empty(), // UPDATE cap query
      empty(), // SELECT expired query
    ]);

    await runAutoCompleteSweep(client, 42);

    assert.equal(client._calls.length, 2);
    const capCall = client._calls[0];
    assert.match(capCall.sql, /^UPDATE activities SET running_since = NULL/i);
    assert.match(capCall.sql, /running_since IS NOT NULL/i);
    assert.equal(capCall.params[0], 42);
    assert.equal(capCall.params[1], 240);
  });

  test('a running row is not paid by the sweep (SELECT excludes running_since IS NOT NULL)', async () => {
    const client = mockClient([
      empty(), // UPDATE cap query
      empty(), // SELECT expired query returns no non-running expired tasks
    ]);

    await runAutoCompleteSweep(client, 42);

    const selectCall = client._calls[1];
    assert.match(selectCall.sql, /^SELECT .* FROM activities/i);
    assert.match(selectCall.sql, /running_since IS NULL/i);
    assert.match(selectCall.sql, /FOR UPDATE/i);
    assert.equal(selectCall.params[0], 42);

    // No updates to family_members or inserts to coin_ledger were made
    assert.equal(client._calls.length, 2);
  });

  test('pays approved expired rows with running_since IS NULL', async () => {
    const expiredTask = {
      id: 10,
      assigned_to: 99,
      type: 'care',
      coin_value: 30,
      bounty_amount: 10,
      bounty_offered_by: 88,
    };

    const client = mockClient([
      empty(),          // UPDATE cap query
      ok([expiredTask]), // SELECT expired query
      empty(),          // UPDATE activities status = 'completed'
      empty(),          // UPDATE family_members coin_balance
      empty(),          // INSERT coin_ledger (value)
      empty(),          // INSERT coin_ledger (bounty)
    ]);

    await runAutoCompleteSweep(client, 42);

    assert.equal(client._calls.length, 6);
    // Verified activity update
    assert.match(client._calls[2].sql, /UPDATE activities SET status = 'completed'/);
    assert.deepStrictEqual(client._calls[2].params, [10]);
    // Verified balance update
    assert.match(client._calls[3].sql, /UPDATE family_members SET coin_balance = coin_balance \+ \$1/);
    assert.deepStrictEqual(client._calls[3].params, [40, 42, 99]);
  });
});
