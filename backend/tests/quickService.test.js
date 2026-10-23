import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import app from '../src/app.js';
import {
  getQuick,
  start,
  done,
  stop,
  undo,
} from '../src/services/quickService.js';
import { RUNNING_CAP_MINUTES } from '../src/db/autoComplete.js';

function mockClient(responses) {
  let idx = 0;
  const calls = [];
  return {
    async query(sql, params) {
      calls.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      if (idx >= responses.length) {
        throw new Error(`Unexpected extra query #${idx}: ${sql.trim().slice(0, 80)}`);
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

describe('getQuick', () => {
  test('returns the correct shape with balance, needsYou, tasks, upcoming, running, serverTime', async () => {
    const familyId = 1;
    const userId = 10;
    const client = mockClient([
      empty(), // sweep cap
      empty(), // sweep expired
      ok([{ id: 1, name: 'The Smiths', balance: 45 }]), // family info
      ok([{ count: 3 }]), // needsYou count
      ok([
        { id: 101, title: 'Task A', type: 'care', duration_minutes: 30, coin_value: 30, category: 'care' },
      ]), // templates
      ok([]), // instances for ranking
      ok([
        {
          id: 201,
          title: 'Upcoming Care',
          type: 'care',
          starts_at: new Date('2026-10-23T12:00:00Z'),
          ends_at: new Date('2026-10-23T12:30:00Z'),
          status: 'approved',
        },
      ]), // upcoming
      empty(), // running
    ]);

    const res = await getQuick(client, userId, familyId);
    assert.ifError(res.error);
    const data = res.data;
    assert.deepEqual(data.family, { id: 1, name: 'The Smiths' });
    assert.equal(data.balance, 45);
    assert.equal(data.needsYou, 3);
    assert.equal(Array.isArray(data.tasks), true);
    assert.equal(data.tasks.length, 1);
    assert.deepEqual(data.tasks[0], {
      id: 101,
      title: 'Task A',
      type: 'care',
      durationMinutes: 30,
      coinValue: 30,
    });
    assert.equal(data.upcoming.length, 1);
    assert.deepEqual(data.upcoming[0], {
      id: 201,
      title: 'Upcoming Care',
      type: 'care',
      startsAt: '2026-10-23T12:00:00.000Z',
      endsAt: '2026-10-23T12:30:00.000Z',
      status: 'approved',
    });
    assert.equal(data.running, null);
    assert.ok(data.serverTime);
  });

  test('tasks is capped at 8', async () => {
    const familyId = 1;
    const userId = 10;
    const templates = Array.from({ length: 12 }, (_, i) => ({
      id: i + 1,
      title: `Task ${String.fromCharCode(65 + i)}`,
      type: 'care',
      duration_minutes: 15,
      coin_value: 15,
      category: 'care',
    }));

    const client = mockClient([
      empty(), // sweep cap
      empty(), // sweep expired
      ok([{ id: 1, name: 'The Smiths', balance: 50 }]),
      ok([{ count: 0 }]),
      ok(templates),
      ok([]), // no ranking instances
      ok([]), // upcoming
      empty(), // running
    ]);

    const res = await getQuick(client, userId, familyId);
    assert.ifError(res.error);
    assert.equal(res.data.tasks.length, 8);
  });

  test('the SQL for templates and instances is scoped to the family and the user', async () => {
    const familyId = 42;
    const userId = 99;
    const client = mockClient([
      empty(), // sweep cap
      empty(), // sweep expired
      ok([{ id: 42, name: 'Family 42', balance: 10 }]),
      ok([{ count: 0 }]),
      ok([]), // templates
      ok([]), // instances
      ok([]), // upcoming
      empty(), // running
    ]);

    await getQuick(client, userId, familyId);

    // Call 4 is templates query
    const tmplCall = client._calls[4];
    assert.ok(tmplCall.sql.includes('family_id = $1'));
    assert.equal(tmplCall.params[0], familyId);

    // Call 5 is instances for ranking query
    const instCall = client._calls[5];
    assert.ok(instCall.sql.includes('family_id = $1'));
    assert.ok(instCall.sql.includes('assigned_to = $2'));
    assert.equal(instCall.params[0], familyId);
    assert.equal(instCall.params[1], userId);
  });

  test('running is null when there is no running row', async () => {
    const client = mockClient([
      empty(),
      empty(),
      ok([{ id: 1, name: 'Fam', balance: 0 }]),
      ok([{ count: 0 }]),
      ok([]),
      ok([]),
      ok([]),
      empty(), // running row empty
    ]);

    const res = await getQuick(client, 1, 1);
    assert.equal(res.data.running, null);
  });

  test('running is populated when a running row exists', async () => {
    const startedAt = new Date('2026-10-23T10:00:00Z');
    const client = mockClient([
      empty(),
      empty(),
      ok([{ id: 1, name: 'Fam', balance: 0 }]),
      ok([{ count: 0 }]),
      ok([]),
      ok([]),
      ok([]),
      ok([{ id: 88, title: 'Running Task', type: 'care', running_since: startedAt, client_ref: 'client-ref-1' }]),
    ]);

    const res = await getQuick(client, 1, 1);
    assert.deepEqual(res.data.running, {
      id: 88,
      title: 'Running Task',
      type: 'care',
      startedAt: '2026-10-23T10:00:00.000Z',
      clientRef: 'client-ref-1',
    });
  });
});

describe('start with a template', () => {
  test('replay returns the existing activity and runs no INSERT', async () => {
    const existing = { id: 77, title: 'Existing', assigned_to: 10, client_ref: 'ref-12345678' };
    const client = mockClient([
      ok([existing]), // replay check matches
    ]);

    const res = await start(client, 10, 1, { templateId: 5, clientRef: 'ref-12345678' });
    assert.ifError(res.error);
    assert.deepEqual(res.data, { activity: existing, replayed: true });
    assert.equal(client._calls.length, 1);
    assert.ok(client._calls[0].sql.includes('client_ref = $2'));
  });

  test('a template from another family -> 404', async () => {
    const client = mockClient([
      empty(), // replay check
      empty(), // template check in family 1 returns nothing
    ]);

    const res = await start(client, 10, 1, { templateId: 999, clientRef: 'ref-12345678' });
    assert.ok(res.error);
    assert.equal(res.error.code, 404);
    assert.equal(res.error.key, 'activityApprovedTemplateNotFound');
  });

  test('the client_ref UPDATE runs after scheduleActivity', async () => {
    const template = {
      id: 5,
      family_id: 1,
      title: 'Bath time',
      type: 'care',
      duration_minutes: 30,
      coin_value: 30,
      status: 'approved',
      is_template: true,
      created_by: 10,
      approved_by: 10,
      approved_at: new Date(),
      is_recurrent: false,
    };
    const scheduled = { ...template, id: 105, is_template: false, assigned_to: 10 };
    const updatedWithRef = { ...scheduled, client_ref: 'ref-12345678' };

    const client = mockClient([
      empty(), // replay check
      ok([template]), // quickService template family check
      // scheduleActivity queries:
      ok([template]), // scheduleActivity tmpl check
      empty(), // absence check
      empty(), // overlap check
      ok([{ monthly_coin_budget: 1000, used_this_month: 0 }]), // budget query
      ok([scheduled]), // INSERT into activities
      // quickService client_ref update:
      ok([updatedWithRef]),
    ]);

    const res = await start(client, 10, 1, { templateId: 5, clientRef: 'ref-12345678' });
    assert.ifError(res.error);
    assert.equal(res.data.activity.client_ref, 'ref-12345678');

    // Verify UPDATE activities SET client_ref ran
    const lastCall = client._calls[client._calls.length - 1];
    assert.ok(lastCall.sql.includes('UPDATE activities SET client_ref = $1 WHERE id = $2'));
    assert.equal(lastCall.params[0], 'ref-12345678');
    assert.equal(lastCall.params[1], 105);
  });
});

describe('start unplanned', () => {
  test('already running -> 409 quickTaskAlreadyRunning', async () => {
    const client = mockClient([
      empty(), // replay check
      ok([{ id: 40, title: 'Currently running task' }]), // running check
    ]);

    const res = await start(client, 10, 1, {
      type: 'care',
      title: 'New unplanned',
      clientRef: 'ref-unplanned-1',
    });
    assert.ok(res.error);
    assert.equal(res.error.code, 409);
    assert.equal(res.error.key, 'quickTaskAlreadyRunning');
    assert.equal(res.error.message, 'You already have a task running.');
    assert.deepEqual(res.error.params, { title: 'Currently running task' });
  });

  test('the INSERT carries running_since and client_ref, with 15 / 15', async () => {
    const insertedRow = {
      id: 55,
      family_id: 1,
      title: 'Care now',
      type: 'care',
      duration_minutes: 15,
      coin_value: 15,
      running_since: new Date(),
      client_ref: 'ref-unplanned-2',
    };
    const client = mockClient([
      empty(), // replay check
      empty(), // running check
      empty(), // absence check
      empty(), // overlap check
      ok([insertedRow]), // INSERT
    ]);

    const res = await start(client, 10, 1, {
      type: 'care',
      title: 'Care now',
      clientRef: 'ref-unplanned-2',
    });
    assert.ifError(res.error);
    assert.deepEqual(res.data.activity, insertedRow);

    const insertCall = client._calls.find((c) => c.sql.startsWith('INSERT INTO activities'));
    assert.ok(insertCall);
    assert.ok(insertCall.sql.includes('running_since'));
    assert.ok(insertCall.sql.includes('client_ref'));
    assert.ok(insertCall.sql.includes('15, 15'));
    assert.deepEqual(insertCall.params, [1, 10, 'Care now', 'care', 'ref-unplanned-2']);
  });

  test('overlap -> scheduleOverlap', async () => {
    const client = mockClient([
      empty(), // replay check
      empty(), // running check
      empty(), // absence check
      ok([{ id: 89, title: 'Existing Scheduled Activity' }]), // overlap check
    ]);

    const res = await start(client, 10, 1, {
      type: 'household',
      title: 'Dishes',
      clientRef: 'ref-unplanned-3',
    });
    assert.ok(res.error);
    assert.equal(res.error.code, 409);
    assert.equal(res.error.key, 'scheduleOverlap');
    assert.deepEqual(res.error.params, { title: 'Existing Scheduled Activity' });
  });

  test('neither or both templateId and type -> 400 quickStartInvalid', async () => {
    const client = mockClient([]);
    const resNeither = await start(client, 10, 1, { clientRef: 'ref-12345678' });
    assert.ok(resNeither.error);
    assert.equal(resNeither.error.code, 400);
    assert.equal(resNeither.error.key, 'quickStartInvalid');

    const resBoth = await start(client, 10, 1, {
      templateId: 1,
      type: 'care',
      clientRef: 'ref-12345678',
    });
    assert.ok(resBoth.error);
    assert.equal(resBoth.error.code, 400);
    assert.equal(resBoth.error.key, 'quickStartInvalid');
  });
});

describe('done with a template', () => {
  test('startsAt equals now minus the duration (allow +/- 5 s)', async () => {
    const now = new Date('2026-10-23T14:30:00.000Z');
    const template = {
      id: 7,
      family_id: 1,
      title: 'Morning Routine',
      type: 'care',
      duration_minutes: 20,
      coin_value: 20,
      status: 'approved',
      is_template: true,
      created_by: 10,
      approved_by: 10,
      approved_at: now,
      is_recurrent: false,
    };
    const scheduled = { id: 107, ...template, is_template: false, assigned_to: 10 };

    const client = mockClient([
      empty(), // replay check
      ok([template]), // quickService template check
      // scheduleActivity queries:
      ok([template]), // scheduleActivity tmpl lookup
      ok([{ user_id: 10 }]), // isPast single caregiver check
      empty(), // absence check
      empty(), // overlap check
      ok([{ monthly_coin_budget: 1000, used_this_month: 0 }]), // budget
      ok([scheduled]), // INSERT
      empty(), // sweep cap
      empty(), // sweep expired
      ok([scheduled]), // query updated row
      ok([scheduled]), // UPDATE client_ref
    ]);

    const res = await done(client, 10, 1, { templateId: 7, clientRef: 'ref-done-123', now });
    assert.ifError(res.error);

    // Verify startsAt passed to scheduleActivity:
    // Expected now - 20 minutes = 14:10:00.000Z
    const expectedTime = new Date('2026-10-23T14:10:00.000Z').getTime();
    const absenceCall = client._calls.find((c) => c.sql.startsWith('SELECT id, title FROM absences'));
    assert.ok(absenceCall);
    const startsAtIso = absenceCall.params[2];
    const actualTime = new Date(startsAtIso).getTime();
    assert.ok(Math.abs(actualTime - expectedTime) <= 5000);
  });

  test('done with templateId requires clientRef -> 400 quickClientRefRequired', async () => {
    const client = mockClient([]);
    const res = await done(client, 10, 1, { templateId: 7 });
    assert.ok(res.error);
    assert.equal(res.error.code, 400);
    assert.equal(res.error.key, 'quickClientRefRequired');
  });

  test('done with activityId calls completeActivity when not running', async () => {
    const activity = {
      id: 401,
      family_id: 1,
      assigned_to: 10,
      running_since: null,
      status: 'approved',
      type: 'care',
      coin_value: 25,
      bounty_amount: 0,
      title: 'Feed pets',
    };
    const client = mockClient([
      ok([activity]), // lookup activity in done
      // completeActivity queries:
      ok([activity]), // completeActivity SELECT FOR UPDATE
      empty(), // UPDATE activities SET status = 'completed'
      empty(), // UPDATE family_members coin_balance
      empty(), // INSERT coin_ledger
    ]);

    const res = await done(client, 10, 1, { activityId: 401 });
    assert.ifError(res.error);
    assert.deepEqual(res.data, { completed: true, coinsAwarded: 25 });
  });

  test('done with activityId calls stop when running_since is set', async () => {
    const now = new Date('2026-10-23T12:30:00.000Z');
    const startsAt = new Date('2026-10-23T12:00:00.000Z');
    const runningActivity = {
      id: 402,
      family_id: 1,
      assigned_to: 10,
      running_since: startsAt,
      starts_at: startsAt,
      status: 'approved',
      type: 'care',
      coin_value: 15,
      bounty_amount: 0,
      title: 'Laundry',
    };
    const client = mockClient([
      ok([runningActivity]), // lookup activity in done
      // stop queries:
      ok([runningActivity]), // SELECT ... FOR UPDATE
      empty(), // UPDATE activities SET running_since = NULL, duration_minutes = 30...
      // completeActivity queries:
      ok([runningActivity]), // SELECT FOR UPDATE
      empty(), // UPDATE status = completed
      empty(), // coin_balance
      empty(), // coin_ledger
    ]);

    const res = await done(client, 10, 1, { activityId: 402, now });
    assert.ifError(res.error);
    assert.deepEqual(res.data, { completed: true, coinsAwarded: 15 });
  });
});

describe('stop', () => {
  test('elapsed 1 min -> 15', async () => {
    const now = new Date('2026-10-23T12:01:00.000Z');
    const startsAt = new Date('2026-10-23T12:00:00.000Z');
    const runningRow = {
      id: 301,
      family_id: 1,
      assigned_to: 10,
      starts_at: startsAt,
      running_since: startsAt,
      type: 'care',
      status: 'approved',
    };
    const client = mockClient([
      ok([runningRow]), // SELECT ... FOR UPDATE
      empty(), // UPDATE activities SET running_since = NULL, duration_minutes = $2...
      // completeActivity queries:
      ok([runningRow]), // SELECT FOR UPDATE
      empty(), // UPDATE activities SET status = 'completed'
      empty(), // UPDATE family_members coin_balance
      empty(), // INSERT coin_ledger
    ]);

    const res = await stop(client, 10, 1, { activityId: 301, now });
    assert.ifError(res.error);
    assert.deepEqual(res.data, { completed: true, coinsAwarded: 0 });

    const updateCall = client._calls[1];
    assert.ok(updateCall.sql.includes('UPDATE activities SET running_since = NULL'));
    assert.equal(updateCall.params[1], 15);

    // Verify completeActivity updated activities status to completed
    const completeCall = client._calls.find((c) => c.sql.includes("UPDATE activities SET status = 'completed'"));
    assert.ok(completeCall, 'completeActivity should have updated status to completed');
  });

  test('elapsed 16 min -> 30', async () => {
    const now = new Date('2026-10-23T12:16:00.000Z');
    const startsAt = new Date('2026-10-23T12:00:00.000Z');
    const runningRow = {
      id: 302,
      family_id: 1,
      assigned_to: 10,
      starts_at: startsAt,
      running_since: startsAt,
      type: 'care',
      status: 'approved',
    };
    const client = mockClient([
      ok([runningRow]), // SELECT ... FOR UPDATE
      empty(), // UPDATE
      ok([runningRow]), // completeActivity SELECT
      empty(), // completeActivity UPDATE status
      empty(), // coin_balance
      empty(), // coin_ledger
    ]);

    await stop(client, 10, 1, { activityId: 302, now });

    const updateCall = client._calls[1];
    assert.equal(updateCall.params[1], 30);
  });

  test('elapsed 300 min -> 240', async () => {
    const now = new Date('2026-10-23T17:00:00.000Z');
    const startsAt = new Date('2026-10-23T12:00:00.000Z');
    const runningRow = {
      id: 303,
      family_id: 1,
      assigned_to: 10,
      starts_at: startsAt,
      running_since: startsAt,
      type: 'care',
      status: 'approved',
    };
    const client = mockClient([
      ok([runningRow]), // SELECT ... FOR UPDATE
      empty(), // UPDATE
      ok([runningRow]), // completeActivity SELECT
      empty(), // completeActivity UPDATE status
      empty(), // coin_balance
      empty(), // coin_ledger
    ]);

    await stop(client, 10, 1, { activityId: 303, now });

    const updateCall = client._calls[1];
    assert.equal(updateCall.params[1], RUNNING_CAP_MINUTES);
    assert.equal(updateCall.params[1], 240);
  });

  test('not running -> 409 quickTaskNotRunning', async () => {
    const client = mockClient([
      empty(), // SELECT ... FOR UPDATE finds no running row
    ]);

    const res = await stop(client, 10, 1, { activityId: 999 });
    assert.ok(res.error);
    assert.equal(res.error.code, 409);
    assert.equal(res.error.key, 'quickTaskNotRunning');
  });
});

describe('undo', () => {
  test('a completed row goes through revert and never DELETEs', async () => {
    const completedAct = {
      id: 501,
      family_id: 1,
      assigned_to: 10,
      status: 'completed',
      type: 'care',
      coin_value: 30,
      bounty_amount: 0,
    };
    const client = mockClient([
      ok([completedAct]), // undo lookup
      // revertActivity queries:
      ok([completedAct]), // revertActivity SELECT ... FOR UPDATE
      empty(), // UPDATE family_members coin_balance
      empty(), // INSERT coin_ledger reversal
      empty(), // UPDATE activities SET status = 'rejected'
    ]);

    const res = await undo(client, 10, 1, { clientRef: 'client-ref-undo-1' });
    assert.ifError(res.error);
    assert.deepEqual(res.data, { undone: true });

    // Assert no DELETE query was called
    const deleteCalls = client._calls.filter((c) => c.sql.startsWith('DELETE'));
    assert.equal(deleteCalls.length, 0);
  });

  test('an approved row goes through delete', async () => {
    const approvedAct = {
      id: 502,
      family_id: 1,
      assigned_to: 10,
      status: 'approved',
      category: 'care',
      type: 'care',
      bounty_amount: 0,
      is_template: false,
    };
    const client = mockClient([
      ok([approvedAct]), // undo lookup
      // deleteActivity queries:
      ok([approvedAct]), // deleteActivity lookup
      empty(), // assertMemberRole check (for caregiver)
      empty(), // DELETE FROM activities WHERE id = $1
    ]);

    const res = await undo(client, 10, 1, { clientRef: 'client-ref-undo-2' });
    assert.ifError(res.error);
    assert.deepEqual(res.data, { undone: true });

    const deleteCalls = client._calls.filter((c) => c.sql.startsWith('DELETE FROM activities'));
    assert.equal(deleteCalls.length, 1);
    assert.equal(deleteCalls[0].params[0], 502);
  });

  test('expired -> 409 quickUndoExpired', async () => {
    const client = mockClient([
      empty(), // undo lookup returns nothing (not found or older than 60s)
    ]);

    const res = await undo(client, 10, 1, { clientRef: 'client-ref-old' });
    assert.ok(res.error);
    assert.equal(res.error.code, 409);
    assert.equal(res.error.key, 'quickUndoExpired');
  });
});

describe('route level authentication', () => {
  test('/api/quick with a Bearer token -> 401 deviceKeyInvalid', async () => {
    const res = await request(app)
      .get('/api/quick')
      .set('Authorization', 'Bearer some-firebase-token');

    assert.equal(res.status, 401);
    assert.equal(res.body.code, 'deviceKeyInvalid');
  });
});
