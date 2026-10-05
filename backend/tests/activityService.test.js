import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  completeActivity,
  validateActivity,
  offerBounty,
  acceptBounty,
  revertActivity,
  listActivities,
  scheduleActivity,
} from '../src/services/activityService.js';

// Builds a mock DB client that responds to queries in order.
// Each entry is either a result object { rows, rowCount } or an Error to throw.
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

const ok = (rows = []) => ({ rows, rowCount: rows.length });
const empty = () => ({ rows: [], rowCount: 0 });

// ─── completeActivity ────────────────────────────────────────────────────────

describe('completeActivity', () => {
  test('awards coin_value to assignee', async () => {
    const inst = { id: 1, family_id: 10, assigned_to: 99, coin_value: 50, bounty_amount: 0, title: 'Walk dog' };
    const client = mockClient([
      ok([inst]),   // SELECT ... FOR UPDATE
      empty(),      // UPDATE activities SET status = 'completed'
      empty(),      // UPDATE family_members coin_balance
      empty(),      // INSERT coin_ledger activity_completed
    ]);
    const result = await completeActivity(client, 99, 1);
    assert.deepEqual(result.data, { completed: true, coinsAwarded: 50 });
  });

  test('awards coin_value + bounty_amount when bounty is set', async () => {
    const inst = { id: 2, family_id: 10, assigned_to: 99, coin_value: 30, bounty_amount: 20, title: 'Cook' };
    const client = mockClient([
      ok([inst]),
      empty(), // UPDATE status
      empty(), // UPDATE coin_balance
      empty(), // INSERT activity_completed
      empty(), // INSERT bounty_earned
    ]);
    const result = await completeActivity(client, 99, 2);
    assert.equal(result.data.coinsAwarded, 50);
  });

  test('returns 404 when activity not found', async () => {
    const client = mockClient([ok([])]); // no rows returned
    const result = await completeActivity(client, 99, 999);
    assert.equal(result.error.code, 404);
  });

  test('awards zero coins when coin_value is 0', async () => {
    const inst = { id: 3, family_id: 10, assigned_to: 99, coin_value: 0, bounty_amount: 0, title: 'Rest' };
    const client = mockClient([
      ok([inst]),
      empty(), // UPDATE status
    ]);
    const result = await completeActivity(client, 99, 3);
    assert.equal(result.data.coinsAwarded, 0);
    assert.equal(client._calls.length, 2); // no coin queries needed
  });
});

// ─── validateActivity ────────────────────────────────────────────────────────

describe('validateActivity', () => {
  test('awards coins to assignee when validated by another user', async () => {
    const act = { id: 5, family_id: 10, assigned_to: 77, status: 'pending_validation', coin_value: 40, bounty_amount: 0 };
    const client = mockClient([
      ok([act]),    // SELECT ... FOR UPDATE
      empty(),      // UPDATE status
      empty(),      // UPDATE coin_balance
      empty(),      // INSERT coin_ledger
    ]);
    const result = await validateActivity(client, 99, 5); // userId=99 != assigned_to=77
    assert.equal(result.data.coinsAwarded, 40);
    assert.equal(result.data.success, true);
  });

  test('returns 403 when user tries to validate their own activity', async () => {
    const act = { id: 6, family_id: 10, assigned_to: 99, status: 'pending_validation', coin_value: 40, bounty_amount: 0 };
    const client = mockClient([ok([act])]);
    const result = await validateActivity(client, 99, 6); // same user
    assert.equal(result.error.code, 403);
  });

  test('returns 409 when activity is not pending_validation', async () => {
    const act = { id: 7, family_id: 10, assigned_to: 77, status: 'completed', coin_value: 40, bounty_amount: 0 };
    const client = mockClient([ok([act])]);
    const result = await validateActivity(client, 99, 7);
    assert.equal(result.error.code, 409);
  });

  test('returns 404 when activity not found', async () => {
    const client = mockClient([ok([])]);
    const result = await validateActivity(client, 99, 999);
    assert.equal(result.error.code, 404);
  });
});

// ─── offerBounty ─────────────────────────────────────────────────────────────

describe('offerBounty', () => {
  test('deducts coins from offerer and sets bounty', async () => {
    const act = { family_id: 10, assigned_to: 99, starts_at: new Date().toISOString() };
    const client = mockClient([
      ok([act]),               // SELECT activity FOR UPDATE
      ok([{ coin_balance: 200 }]), // SELECT coin_balance
      empty(),                 // UPDATE coin_balance -
      empty(),                 // INSERT coin_ledger bounty_escrow
      empty(),                 // UPDATE activities bounty_amount
    ]);
    const result = await offerBounty(client, 99, 1, 50);
    assert.equal(result.data.success, true);
  });

  test('returns 403 when user is not the assignee', async () => {
    const act = { family_id: 10, assigned_to: 77, starts_at: new Date().toISOString() };
    const client = mockClient([ok([act])]);
    const result = await offerBounty(client, 99, 1, 50);
    assert.equal(result.error.code, 403);
  });

  test('returns 409 when user has insufficient coins', async () => {
    const act = { family_id: 10, assigned_to: 99, starts_at: new Date().toISOString() };
    const client = mockClient([
      ok([act]),
      ok([{ coin_balance: 10 }]), // less than bountyAmount=50
    ]);
    const result = await offerBounty(client, 99, 1, 50);
    assert.equal(result.error.code, 409);
    assert.match(result.error.message, /Insufficient/);
  });

  test('returns 404 when activity not found', async () => {
    const client = mockClient([ok([])]);
    const result = await offerBounty(client, 99, 999, 50);
    assert.equal(result.error.code, 404);
  });
});

// ─── acceptBounty ────────────────────────────────────────────────────────────

describe('acceptBounty', () => {
  test('reassigns activity to accepting user', async () => {
    const act = { family_id: 10, assigned_to: 77, bounty_amount: 50, bounty_offered_by: 77, status: 'approved' };
    const client = mockClient([
      ok([act]),
      empty(), // UPDATE assigned_to
    ]);
    const result = await acceptBounty(client, 99, 1);
    assert.equal(result.data.success, true);
  });

  test('returns 409 when user already owns the shift', async () => {
    const act = { family_id: 10, assigned_to: 99, bounty_amount: 50, bounty_offered_by: 99, status: 'approved' };
    const client = mockClient([ok([act])]);
    const result = await acceptBounty(client, 99, 1);
    assert.equal(result.error.code, 409);
    assert.match(result.error.message, /already own/);
  });

  test('returns 409 when activity is completed', async () => {
    const act = { family_id: 10, assigned_to: 77, bounty_amount: 50, bounty_offered_by: 77, status: 'completed' };
    const client = mockClient([ok([act])]);
    const result = await acceptBounty(client, 99, 1);
    assert.equal(result.error.code, 409);
  });

  test('returns 409 when no bounty is set', async () => {
    const act = { family_id: 10, assigned_to: 77, bounty_amount: null, bounty_offered_by: null, status: 'approved' };
    const client = mockClient([ok([act])]);
    const result = await acceptBounty(client, 99, 1);
    assert.equal(result.error.code, 409);
    assert.match(result.error.message, /No bounty/);
  });
});

// ─── revertActivity ──────────────────────────────────────────────────────────

describe('revertActivity', () => {
  test('deducts coins and marks activity as rejected', async () => {
    const act = { family_id: 10, assigned_to: 99, status: 'completed', coin_value: 60, bounty_amount: 0, bounty_offered_by: null };
    const client = mockClient([
      ok([act]),   // SELECT FOR UPDATE
      empty(),     // UPDATE family_members - coins
      empty(),     // INSERT coin_ledger activity_reverted
      empty(),     // UPDATE activities SET status = 'rejected'
    ]);
    const result = await revertActivity(client, 99, 1);
    assert.equal(result.data.coinsDeducted, 60);
  });

  test('appends a reversal instead of rewriting the credit', async () => {
    const act = { family_id: 10, assigned_to: 99, status: 'completed', type: 'care', coin_value: 60, bounty_amount: 0, bounty_offered_by: null };
    const client = mockClient([ok([act]), empty(), empty(), empty()]);
    await revertActivity(client, 99, 1);
    assert.ok(client._calls.every(c => !/UPDATE coin_ledger/.test(c.sql)), 'ledger rows must never be rewritten');
    const reversal = client._calls[2];
    assert.match(reversal.sql, /INSERT INTO coin_ledger/);
    assert.deepEqual(reversal.params, [10, 99, 1, -60, 'activity_reverted']);
  });

  test('a coverage shift is reversed under coverage reasons', async () => {
    const act = { family_id: 10, assigned_to: 99, status: 'completed', type: 'coverage', coin_value: 40, bounty_amount: 5, bounty_offered_by: 77 };
    const client = mockClient([ok([act]), empty(), empty(), empty(), empty(), empty(), empty()]);
    await revertActivity(client, 99, 1);
    assert.deepEqual(client._calls[2].params, [10, 99, 1, -40, 'coverage_reverted']);
    assert.deepEqual(client._calls[3].params, [10, 99, 1, -5, 'coverage_sweetener_reverted']);
    assert.deepEqual(client._calls[5].params, [10, 77, 1, 5, 'coverage_sweetener_refunded']);
  });

  test('refunds bounty to original offerer on revert', async () => {
    const act = { family_id: 10, assigned_to: 99, status: 'completed', coin_value: 30, bounty_amount: 20, bounty_offered_by: 77 };
    const client = mockClient([
      ok([act]),
      empty(), // UPDATE family_members - totalAward
      empty(), // INSERT coin_ledger activity_reverted
      empty(), // INSERT coin_ledger bounty_reverted
      empty(), // UPDATE family_members + bountyAmt for offerer
      empty(), // INSERT coin_ledger bounty_refunded
      empty(), // UPDATE activities SET status = 'rejected'
    ]);
    const result = await revertActivity(client, 99, 1);
    assert.equal(result.data.coinsDeducted, 50);
  });

  test('returns 403 when user is not the assignee', async () => {
    const act = { family_id: 10, assigned_to: 77, status: 'completed', coin_value: 30, bounty_amount: 0, bounty_offered_by: null };
    const client = mockClient([ok([act])]);
    const result = await revertActivity(client, 99, 1);
    assert.equal(result.error.code, 403);
  });

  test('returns 409 when activity is not completed', async () => {
    const act = { family_id: 10, assigned_to: 99, status: 'approved', coin_value: 30, bounty_amount: 0, bounty_offered_by: null };
    const client = mockClient([ok([act])]);
    const result = await revertActivity(client, 99, 1);
    assert.equal(result.error.code, 409);
  });
});

// ─── listActivities ──────────────────────────────────────────────────────────

describe('listActivities', () => {
  test('returns 403 when user is not a family member', async () => {
    // assertActiveMember queries family_members and returns rowCount 0
    const client = mockClient([{ rows: [], rowCount: 0 }]);
    const result = await listActivities(client, 99, 10);
    assert.equal(result.error.code, 403);
  });
});

// ─── scheduleActivity ────────────────────────────────────────────────────────

describe('scheduleActivity', () => {
  const tmpl = {
    id: 5, family_id: 10, created_by: 98, title: 'Dinner', type: 'meals',
    duration_minutes: 60, coin_value: 60, approved_by: 98, approved_at: '2030-01-01T00:00:00Z',
    is_recurrent: false,
  };
  const futureStart = '2030-06-01T19:00:00Z';

  test('returns 409 when the user already has an activity in that slot', async () => {
    const client = mockClient([
      ok([tmpl]),                          // SELECT template
      empty(),                             // absence overlap
      ok([{ id: 7, title: 'Bath time' }]), // self overlap
    ]);
    const result = await scheduleActivity(client, 99, 5, futureStart);
    assert.equal(result.error.code, 409);
    assert.match(result.error.message, /Bath time/);
  });

  test('lets a task be scheduled inside a coverage window', async () => {
    // Coverage is supervision, not busy hands: someone covering a dependent
    // still cooks dinner inside that window, so the check must skip those rows
    // or accepting coverage would freeze the rest of their evening.
    const scheduled = { id: 9, family_id: 10, assigned_to: 99, title: 'Dinner' };
    const client = mockClient([
      ok([tmpl]),                                              // SELECT template
      empty(),                                                 // absence overlap
      empty(),                                                 // self overlap
      ok([{ monthly_coin_budget: 1000, used_this_month: 0 }]), // budget
      ok([scheduled]),                                         // INSERT
    ]);
    await scheduleActivity(client, 99, 5, futureStart);
    assert.match(client._calls[2].sql, /type <> 'coverage'/);
  });

  test('scopes the overlap check to the scheduling user, so other caretakers can share the slot', async () => {
    const scheduled = { id: 8, family_id: 10, assigned_to: 99, title: 'Dinner' };
    const client = mockClient([
      ok([tmpl]),                                                  // SELECT template
      empty(),                                                     // absence overlap
      empty(),                                                     // self overlap
      ok([{ monthly_coin_budget: 1000, used_this_month: 0 }]),     // budget
      ok([scheduled]),                                             // INSERT
    ]);
    const result = await scheduleActivity(client, 99, 5, futureStart);
    assert.equal(result.data.id, 8);
    const overlapCall = client._calls[2];
    assert.match(overlapCall.sql, /assigned_to = \$1/);
    assert.equal(overlapCall.params[0], 99);
  });
});
