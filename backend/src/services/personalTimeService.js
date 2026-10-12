import { assertActiveMember } from '../db/users.js';
import { serviceError } from '../utils/httpError.js';

/**
 * Personal-time requests (docs/personal-time-plan.md §3.2, Phase 4).
 *
 * Booking time for yourself always carries a coverage offer to another
 * caretaker, and is only real once they accept — you cannot decline your
 * partner's business trip, but you can decline their gym session.
 *
 * Nothing is scheduled while a request is pending. On acceptance two ordinary
 * `activities` rows are materialized: the requester's self activity (worth
 * nothing) and the accepter's coverage shift (worth the family base rate, plus
 * whatever the requester put up from their own wallet). Every existing query
 * over `activities` therefore keeps working untouched.
 */

export const SELF_TYPES = ['sport', 'social', 'rest', 'appointment', 'other'];

export const MIN_MINUTES = 15;
export const MAX_HOURS = 24;
export const RECURRENCES = ['daily', 'weekdays', 'weekly'];

/** However far out the end date is, no series may materialize more than this. */
export const MAX_OCCURRENCES = 60;
const DEFAULT_EXPIRY_HOURS = 48;
const MS_PER_MINUTE = 60_000;

// ─── Pure rules ───────────────────────────────────────────────────────────────

/**
 * Validates the window a self activity claims. Returns an error descriptor with
 * { key, message, params }, or null when usable.
 */
export function selfWindowError(startsAt, endsAt, now = new Date()) {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    return { key: 'timeWindowInvalidDates', message: 'Start and end must be valid date/time values.' };
  }
  if (end.getTime() <= start.getTime()) {
    return { key: 'timeWindowEndBeforeStart', message: 'End time must be after start time.' };
  }
  const minutes = (end.getTime() - start.getTime()) / MS_PER_MINUTE;
  if (minutes < MIN_MINUTES) {
    return {
      key: 'personalTimeTooShort',
      message: `Personal time must last at least ${MIN_MINUTES} minutes.`,
      params: { minutes: MIN_MINUTES },
    };
  }
  if (minutes > MAX_HOURS * 60) {
    return {
      key: 'personalTimeTooLong',
      message: `Personal time cannot exceed ${MAX_HOURS} hours — log time off instead.`,
      params: { hours: MAX_HOURS },
    };
  }
  if (end.getTime() <= now.getTime()) {
    return { key: 'personalTimeInPast', message: 'Personal time must be in the future.' };
  }
  return null;
}

/**
 * Validates the window a self activity claims. Returns an error message, or
 * null when usable. Pure, so the rule is unit-testable without a database.
 */
export function validateSelfWindow(startsAt, endsAt, now = new Date()) {
  return selfWindowError(startsAt, endsAt, now)?.message ?? null;
}

/**
 * What covering that window is worth, using the same rule the activities screen
 * suggests for every other task: round(rate × hours), floored at 1.
 */
export function priceCoverage(baseRatePerHour, minutes) {
  return Math.max(1, Math.round((baseRatePerHour * minutes) / 60));
}

/** Requests go stale 48 h after asking, or when the window starts — whichever is sooner. */
export function expiryFor(startsAt, now = new Date()) {
  const cap = new Date(now.getTime() + DEFAULT_EXPIRY_HOURS * 60 * 60 * 1000);
  const start = new Date(startsAt);
  return start < cap ? start : cap;
}

const isWeekend = (d) => d.getDay() === 0 || d.getDay() === 6;

/**
 * End of the given day, local. `recurrence_until` arrives either as a DATE row
 * from pg or as a 'YYYY-MM-DD' string from the API, and a date-only string
 * parses as UTC midnight — which `setHours` would then drag back a day for any
 * server west of UTC. Parsing the parts explicitly makes the boundary the same
 * day everywhere. (`createRecurrence` still has that off-by-one; this does not
 * copy it, because copying a bug is not the kind of consistency worth having.)
 */
function endOfDay(until) {
  const parts = typeof until === 'string' ? /^(\d{4})-(\d{2})-(\d{2})/.exec(until) : null;
  const day = parts
    ? new Date(Number(parts[1]), Number(parts[2]) - 1, Number(parts[3]))
    : new Date(until);
  if (Number.isNaN(day.getTime())) return null;
  day.setHours(23, 59, 59, 999);
  return day;
}

/**
 * Every window a request covers, as `{ occurrences, error, key, params }`. A request with no
 * recurrence yields exactly one — its own window.
 *
 * Unlike `createRecurrence` in activityService, which excludes its seed because
 * that instance already exists, this starts *at* `startsAt`: nothing has been
 * scheduled yet, so the first window is part of what is being asked for.
 *
 * The step arithmetic deliberately mirrors `createRecurrence` — `setDate` in
 * server-local time — and carries the same DST caveat: across a transition the
 * wall-clock hour is preserved in the server's timezone rather than the
 * family's, so the UTC instant moves by an hour. Consistency with the existing
 * convention beats a lone correct-but-different implementation; fixing it is a
 * job for both call sites at once.
 */
export function occurrencesFor(startsAt, endsAt, recurrence = null, until = null) {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  const durationMs = end.getTime() - start.getTime();
  const one = { occurrences: [{ start, end }], error: null };
  const refuse = (key, error, params) => ({ occurrences: [], error, key, ...(params ? { params } : {}) });

  if (!recurrence) return one;
  if (!RECURRENCES.includes(recurrence)) {
    return refuse('recurrenceInvalidType', `Repeat must be one of: ${RECURRENCES.join(', ')}.`);
  }
  if (!until) return refuse('recurrenceMissingUntil', 'A repeating request needs a date to repeat until.');

  const last = endOfDay(until);
  if (!last) return refuse('recurrenceInvalidDate', 'The repeat end date is not a valid date.');
  if (last < start) return refuse('recurrenceEndBeforeStart', 'The repeat end date is before the first occurrence.');
  if (recurrence === 'weekdays' && isWeekend(start)) {
    return refuse('recurrenceWeekdaysOnWeekend', 'A weekdays repeat has to start on a weekday.');
  }

  const occurrences = [];
  const current = new Date(start);
  while (current <= last) {
    if (!(recurrence === 'weekdays' && isWeekend(current))) {
      occurrences.push({
        start: new Date(current),
        end: new Date(current.getTime() + durationMs),
      });
      // Refuse rather than truncate: a series quietly cut to 60 would escrow
      // for 60 while the requester believed they had asked for more.
      if (occurrences.length > MAX_OCCURRENCES) {
        return refuse(
          'recurrenceTooManyOccurrences',
          `A repeating request cannot cover more than ${MAX_OCCURRENCES} occurrences — pick a nearer end date.`,
          { max: MAX_OCCURRENCES }
        );
      }
    }
    current.setDate(current.getDate() + (recurrence === 'weekly' ? 7 : 1));
  }
  return { occurrences, error: null };
}

// ─── Shared queries ───────────────────────────────────────────────────────────

async function activeCaregivers(client, familyId) {
  const { rows } = await client.query(
    `SELECT fm.user_id, COALESCE(fm.alias, u.display_name, u.email) AS name
     FROM family_members fm JOIN users u ON u.id = fm.user_id
     WHERE fm.family_id = $1 AND fm.role = 'caregiver' AND fm.status = 'active'
     ORDER BY fm.id`,
    [familyId]
  );
  return rows;
}

/**
 * Who to ask. Two caregivers is the common case and needs no picker — it is the
 * other one. With three or more, an unspecified counterparty means "ask anyone".
 */
function resolveCounterparty(caregivers, requesterId, requestedOf) {
  if (requestedOf) {
    const match = caregivers.find((c) => Number(c.user_id) === Number(requestedOf));
    if (!match) return { error: 'That person is not an active caregiver in this family.', key: 'personalTimeCaregiverNotFound' };
    if (Number(requestedOf) === Number(requesterId)) {
      return { error: 'You cannot ask yourself to cover.', key: 'personalTimeCannotAskSelf' };
    }
    return { requestedOf: Number(requestedOf) };
  }
  const others = caregivers.filter((c) => Number(c.user_id) !== Number(requesterId));
  if (others.length === 1) return { requestedOf: Number(others[0].user_id) };
  if (others.length === 0) return { error: 'There is no one else to cover for you.', key: 'personalTimeNoOneToCover' };
  return { requestedOf: null }; // ask anyone
}

/** What else sits in that window for a given person, ignoring coverage (§4.1). */
async function conflictsFor(client, familyId, userId, startsAt, endsAt) {
  const { rows: absences } = await client.query(
    `SELECT title FROM absences
     WHERE user_id = $1 AND family_id = $2 AND start_time < $4 AND end_time > $3`,
    [userId, familyId, startsAt, endsAt]
  );
  const { rows: busy } = await client.query(
    `SELECT title FROM activities
     WHERE assigned_to = $1 AND family_id = $2 AND is_template = false
       AND type <> 'coverage'
       AND status IN ('approved', 'pending_validation')
       AND starts_at < $4 AND ends_at > $3`,
    [userId, familyId, startsAt, endsAt]
  );
  return [...absences.map((a) => a.title), ...busy.map((b) => b.title)];
}

async function baseRateFor(client, familyId) {
  const { rows } = await client.query(
    'SELECT monthly_coin_budget FROM families WHERE id = $1',
    [familyId]
  );
  return rows.length ? rows[0].monthly_coin_budget / 720 : 0;
}

/**
 * Credits `amount` of a request's escrow back to whoever asked, and writes the
 * escrow down by what it returned. Reading the amount off `escrowed_coins`
 * rather than recomputing it from the occurrence list is the whole reason that
 * column exists: a refund that recomputes is a refund that can drift.
 *
 * Zeroing the column as it pays is also what makes refunding idempotent — a
 * second sweep over the same row finds nothing left to give back.
 */
async function refundEscrow(client, req, amount = Number(req.escrowed_coins) || 0) {
  const refund = Math.min(Math.max(0, amount), Number(req.escrowed_coins) || 0);
  if (!refund) return 0;
  await client.query(
    'UPDATE family_members SET coin_balance = coin_balance + $1 WHERE family_id = $2 AND user_id = $3',
    [refund, req.family_id, req.requester_id]
  );
  await client.query(
    `INSERT INTO coin_ledger (family_id, user_id, amount, reason)
     VALUES ($1, $2, $3, 'coverage_sweetener_refunded')`,
    [req.family_id, req.requester_id, refund]
  );
  await client.query(
    'UPDATE personal_time_requests SET escrowed_coins = escrowed_coins - $1 WHERE id = $2',
    [refund, req.id]
  );
  return refund;
}

// ─── Operations ───────────────────────────────────────────────────────────────

export async function quoteRequest(client, userId, { familyId, startsAt, endsAt, requestedOf, coverageNeeded = true, recurrence = null, recurrenceUntil = null }, now = new Date()) {
  if (!await assertActiveMember(client, familyId, userId)) {
    return serviceError(403, 'familyNotMember', 'Not a family member.');
  }
  const windowErr = selfWindowError(startsAt, endsAt, now);
  if (windowErr) return serviceError(400, windowErr.key, windowErr.message, windowErr.params);

  // The sheet must be able to show what a series really costs before it is
  // asked for, and the occurrence count is the server's to decide.
  const { occurrences, error: repeatError, key: repeatKey, params: repeatParams } = occurrencesFor(startsAt, endsAt, recurrence, recurrenceUntil);
  if (repeatError) return serviceError(400, repeatKey, repeatError, repeatParams);

  const minutes = (new Date(endsAt) - new Date(startsAt)) / MS_PER_MINUTE;
  // The sheet lists candidates whether or not coverage is wanted, so this is
  // needed either way — see `candidates` below.
  const caregivers = await activeCaregivers(client, familyId);
  // Only coverage needs a counterparty. Time booked with `coverageNeeded:
  // false` asks nobody to stand in, so resolving one there would reject a lone
  // caregiver's own booking with "There is no one else to cover for you."
  let resolved = { requestedOf: null };
  if (coverageNeeded) {
    resolved = resolveCounterparty(caregivers, userId, requestedOf);
    if (resolved.error) return serviceError(400, resolved.key, resolved.error);
  }

  const baseline = coverageNeeded ? priceCoverage(await baseRateFor(client, familyId), minutes) : 0;

  const { rows: balanceRows } = await client.query(
    'SELECT coin_balance FROM family_members WHERE family_id = $1 AND user_id = $2',
    [familyId, userId]
  );

  // Their conflicts are a warning, never a refusal — they may rearrange.
  const theirConflicts = resolved.requestedOf
    ? await conflictsFor(client, familyId, resolved.requestedOf, startsAt, endsAt)
    : [];

  return {
    data: {
      baselineCoins: baseline,
      minutes,
      requestedOf: resolved.requestedOf,
      candidates: caregivers.filter((c) => Number(c.user_id) !== Number(userId)),
      yourBalance: balanceRows[0]?.coin_balance ?? 0,
      theirConflicts,
      occurrences: occurrences.length,
      expiresAt: expiryFor(startsAt, now).toISOString(),
    },
  };
}

/**
 * Refunds and closes pending requests nobody answered in time.
 *
 * Driven from `listRequests` rather than from `runAutoCompleteSweep`: the
 * personal-time domain sweeping its own stale rows is cleaner than piggybacking
 * on the activity sweep, and runs just as often now that both calendars list
 * requests. It shares the monthly distribution's limitation — if nobody opens
 * the app, nothing expires — which is acceptable because `acceptRequest`
 * already refuses an expired request. This sweep is about the money, not
 * about correctness.
 */
export async function expireStaleRequests(client, familyId, now = new Date()) {
  const { rows } = await client.query(
    `SELECT * FROM personal_time_requests
     WHERE family_id = $1 AND status = 'pending' AND expires_at <= $2::timestamptz
     FOR UPDATE`,
    [familyId, now.toISOString()]
  );
  let refunded = 0;
  for (const request of rows) {
    refunded += await refundEscrow(client, request);
    await client.query(
      `UPDATE personal_time_requests SET status = 'expired' WHERE id = $1`,
      [request.id]
    );
  }
  return { expired: rows.length, refunded };
}

export async function listRequests(client, userId, familyId, now = new Date()) {
  if (!await assertActiveMember(client, familyId, userId)) {
    return serviceError(403, 'familyNotMember', 'Not a family member.');
  }
  await expireStaleRequests(client, familyId, now);
  const { rows } = await client.query(
    `SELECT r.*,
            COALESCE(rm.alias, ru.display_name) AS requester_name,
            COALESCE(om.alias, ou.display_name) AS requested_of_name
     FROM personal_time_requests r
     JOIN users ru ON ru.id = r.requester_id
     LEFT JOIN family_members rm ON rm.user_id = r.requester_id AND rm.family_id = r.family_id
     LEFT JOIN users ou ON ou.id = r.requested_of
     LEFT JOIN family_members om ON om.user_id = r.requested_of AND om.family_id = r.family_id
     WHERE r.family_id = $1
     ORDER BY r.starts_at ASC`,
    [familyId]
  );
  return { data: { requests: rows } };
}

export async function createRequest(client, userId, body, now = new Date()) {
  const {
    familyId, title, type, description = null,
    startsAt, endsAt, requestedOf = null,
    coverageNeeded = true, sweetenerCoins = 0,
    recurrence = null, recurrenceUntil = null,
  } = body;

  if (!await assertActiveMember(client, familyId, userId)) {
    return serviceError(403, 'familyNotMember', 'Not a family member.');
  }
  if (!SELF_TYPES.includes(type)) {
    return serviceError(400, 'personalTimeInvalidType', `type must be one of: ${SELF_TYPES.join(', ')}.`);
  }
  const windowErr = selfWindowError(startsAt, endsAt, now);
  if (windowErr) return serviceError(400, windowErr.key, windowErr.message, windowErr.params);

  const yourConflicts = await conflictsFor(client, familyId, userId, startsAt, endsAt);
  if (yourConflicts.length) {
    return serviceError(
      409,
      'personalTimeRequesterBusy',
      `You already have "${yourConflicts[0]}" during this time.`,
      { title: yourConflicts[0] }
    );
  }

  // Only coverage needs a counterparty. Time booked with `coverageNeeded:
  // false` asks nobody to stand in, so resolving one there would reject a lone
  // caregiver's own booking with "There is no one else to cover for you."
  let resolved = { requestedOf: null };
  if (coverageNeeded) {
    const caregivers = await activeCaregivers(client, familyId);
    resolved = resolveCounterparty(caregivers, userId, requestedOf);
    if (resolved.error) return serviceError(400, resolved.key, resolved.error);
  }

  const { occurrences, error: repeatError, key: repeatKey, params: repeatParams } = occurrencesFor(startsAt, endsAt, recurrence, recurrenceUntil);
  if (repeatError) return serviceError(400, repeatKey, repeatError, repeatParams);

  const minutes = (new Date(endsAt) - new Date(startsAt)) / MS_PER_MINUTE;
  const baseline = coverageNeeded ? priceCoverage(await baseRateFor(client, familyId), minutes) : 0;
  // The sweetener is priced per occurrence: ten Fridays at 5 cc is ten favours
  // asked, not one, so the whole 50 leaves the wallet now.
  const sweetener = coverageNeeded ? Math.max(0, Math.trunc(Number(sweetenerCoins) || 0)) : 0;
  const escrow = sweetener * occurrences.length;

  if (escrow > 0) {
    const { rows } = await client.query(
      `SELECT coin_balance FROM family_members
       WHERE family_id = $1 AND user_id = $2 AND status = 'active' FOR UPDATE`,
      [familyId, userId]
    );
    if (!rows.length || rows[0].coin_balance < escrow) {
      return occurrences.length > 1
        ? serviceError(
            409,
            'personalTimeSweetenerSeriesTooExpensive',
            `Sweetening all ${occurrences.length} occurrences costs ${escrow} coins, which is more than you have.`,
            { occurrences: occurrences.length, escrow }
          )
        : serviceError(409, 'personalTimeSweetenerInsufficientCoins', 'You do not have enough coins to sweeten this offer.');
    }
    // Escrowed now, exactly as offerBounty does, so the coins cannot be spent
    // twice while the request is outstanding.
    await client.query(
      'UPDATE family_members SET coin_balance = coin_balance - $1 WHERE family_id = $2 AND user_id = $3',
      [escrow, familyId, userId]
    );
    await client.query(
      `INSERT INTO coin_ledger (family_id, user_id, amount, reason)
       VALUES ($1, $2, $3, 'coverage_sweetener_escrow')`,
      [familyId, userId, -escrow]
    );
  }

  // Nobody has to answer a request that needs no coverage; it is recorded as
  // already settled, with responded_by NULL to show no one was asked to decide.
  const status = coverageNeeded ? 'pending' : 'accepted';

  const { rows } = await client.query(
    `INSERT INTO personal_time_requests
       (family_id, requester_id, requested_of, title, type, description,
        starts_at, ends_at, coverage_needed, baseline_coins, sweetener_coins,
        status, responded_at, expires_at,
        escrowed_coins, recurrence, recurrence_until)
     VALUES ($1,$2,$3,$4,$5,$6,$7::timestamptz,$8::timestamptz,$9,$10,$11,$12,$13,$14::timestamptz,
             $15,$16,$17::date)
     RETURNING *`,
    [
      familyId, userId, resolved.requestedOf, title.trim(), type, description,
      startsAt, endsAt, coverageNeeded, baseline, sweetener,
      status, coverageNeeded ? null : now.toISOString(),
      expiryFor(startsAt, now).toISOString(),
      escrow, recurrence, recurrence ? recurrenceUntil : null,
    ]
  );
  const request = rows[0];

  // With no coverage to negotiate the self activities are booked straight away
  // — every occurrence of them, not just the first.
  if (!coverageNeeded) {
    for (const slot of occurrences) await insertSelfActivity(client, request, null, slot);
  }

  const theirConflicts = resolved.requestedOf
    ? await conflictsFor(client, familyId, resolved.requestedOf, startsAt, endsAt)
    : [];

  return { data: request, warnings: theirConflicts };
}

/** `slot` is the occurrence being booked; without one it is the request's own window. */
async function insertSelfActivity(client, request, counterpartId = null, slot = null) {
  const startsAt = slot ? slot.start.toISOString() : request.starts_at;
  const endsAt = slot ? slot.end.toISOString() : request.ends_at;
  const { rows } = await client.query(
    `INSERT INTO activities
       (family_id, created_by, assigned_to, title, category, type, description,
        starts_at, ends_at, duration_minutes, coin_value, status, is_template,
        personal_time_request_id, counterpart_activity_id)
     VALUES ($1,$2,$2,$3,'self',$4,$5,$6::timestamptz,$7::timestamptz,
             EXTRACT(EPOCH FROM ($7::timestamptz - $6::timestamptz))/60, 0, 'approved', false, $8, $9)
     RETURNING *`,
    [request.family_id, request.requester_id, request.title, request.type,
     request.description, startsAt, endsAt, request.id, counterpartId]
  );
  return rows[0];
}

export async function acceptRequest(client, userId, requestId, now = new Date()) {
  const { rows } = await client.query(
    'SELECT * FROM personal_time_requests WHERE id = $1 FOR UPDATE',
    [requestId]
  );
  if (!rows.length) return serviceError(404, 'personalTimeRequestNotFound', 'Request not found.');
  const request = rows[0];

  if (!await assertActiveMember(client, request.family_id, userId)) {
    return serviceError(403, 'familyNotMember', 'Not a family member.');
  }
  if (request.status !== 'pending') {
    return serviceError(409, 'personalTimeRequestAlreadySettled', `This request is already ${request.status}.`, { status: request.status });
  }
  if (new Date(request.expires_at) <= now) {
    return serviceError(409, 'personalTimeRequestExpired', 'This request has expired.');
  }
  if (Number(request.requester_id) === Number(userId)) {
    return serviceError(403, 'personalTimeCannotCoverSelf', 'You cannot cover your own personal time.');
  }
  if (request.requested_of && Number(request.requested_of) !== Number(userId)) {
    return serviceError(403, 'personalTimeAddressedToOther', 'This request was addressed to someone else.');
  }
  const caregivers = await activeCaregivers(client, request.family_id);
  if (!caregivers.some((c) => Number(c.user_id) === Number(userId))) {
    return serviceError(403, 'personalTimeOnlyCaregiversCanCover', 'Only caregivers can cover.');
  }

  const { occurrences, error: repeatError, key: repeatKey, params: repeatParams } = occurrencesFor(
    request.starts_at, request.ends_at, request.recurrence, request.recurrence_until
  );
  if (repeatError) return serviceError(409, repeatKey, repeatError, repeatParams);

  // The coverage shift is inserted directly rather than through
  // scheduleActivity: it is allowed to overlap whatever else they have on.
  const minutes = `EXTRACT(EPOCH FROM ($6::timestamptz - $5::timestamptz))/60`;

  const pairs = [];
  let skipped = 0;
  let blocked = null; // why the first unusable occurrence was unusable

  for (const slot of occurrences) {
    const startIso = slot.start.toISOString();
    const endIso = slot.end.toISOString();

    // Being away is the one thing that makes covering impossible; anything else
    // in their calendar is fine, because coverage nests (§4.1).
    const { rows: away } = await client.query(
      `SELECT title FROM absences
       WHERE user_id = $1 AND family_id = $2 AND start_time < $4 AND end_time > $3`,
      [userId, request.family_id, startIso, endIso]
    );
    if (away.length) {
      blocked ??= {
        key: 'personalTimeCovererAway',
        message: `You are away ("${away[0].title}") during this time.`,
        params: { title: away[0].title },
      };
      skipped++;
      continue;
    }

    // And there is no point covering a window the requester has since filled.
    const theirs = await conflictsFor(
      client, request.family_id, request.requester_id, startIso, endIso
    );
    if (theirs.length) {
      blocked ??= {
        key: 'personalTimeRequesterConflict',
        message: `They already have "${theirs[0]}" during this time.`,
        params: { title: theirs[0] },
      };
      skipped++;
      continue;
    }

    const { rows: coverRows } = await client.query(
      `INSERT INTO activities
         (family_id, created_by, assigned_to, title, category, type, description,
          starts_at, ends_at, duration_minutes, coin_value, status, is_template,
          bounty_amount, bounty_offered_by, personal_time_request_id)
       VALUES ($1,$2,$3,$4,'care','coverage',$7,$5::timestamptz,$6::timestamptz,
               ${minutes}, $8, 'approved', false, $9, $2, $10)
       RETURNING *`,
      [request.family_id, request.requester_id, userId,
       `Covering for ${request.title}`, startIso, endIso,
       request.description, request.baseline_coins, request.sweetener_coins, request.id]
    );
    const coverage = coverRows[0];

    const self = await insertSelfActivity(client, request, coverage.id, slot);
    await client.query(
      'UPDATE activities SET counterpart_activity_id = $1 WHERE id = $2',
      [self.id, coverage.id]
    );
    pairs.push({ selfActivityId: self.id, coverageActivityId: coverage.id });
  }

  // Nothing usable is a refusal, not an acceptance of nothing: the request stays
  // pending, its escrow untouched, and someone else may still be able to take it.
  if (!pairs.length) {
    if (occurrences.length === 1) {
      return serviceError(409, blocked.key, blocked.message, blocked.params);
    }
    return serviceError(
      409,
      'personalTimeSeriesBlocked',
      `None of the ${occurrences.length} occurrences work — ${blocked.message}`,
      // The reason travels as its own code so the app can translate both halves.
      {
        occurrences: occurrences.length,
        reasonCode: blocked.key,
        ...(blocked.params ? { reasonParams: blocked.params } : {}),
      }
    );
  }

  // The escrow bought favours; the skipped ones will not happen, so that part of
  // it goes home. What remains rides out on each shift's `bounty_amount`.
  const refunded = await refundEscrow(client, request, request.sweetener_coins * skipped);

  await client.query(
    `UPDATE personal_time_requests
     SET status = 'accepted', responded_by = $1, responded_at = $2::timestamptz
     WHERE id = $3`,
    [userId, now.toISOString(), request.id]
  );

  return {
    data: {
      accepted: true,
      created: pairs.length,
      skipped,
      refunded,
      selfActivityId: pairs[0].selfActivityId,
      coverageActivityId: pairs[0].coverageActivityId,
    },
    request,
  };
}

export async function declineRequest(client, userId, requestId, now = new Date()) {
  const { rows } = await client.query(
    'SELECT * FROM personal_time_requests WHERE id = $1 FOR UPDATE',
    [requestId]
  );
  if (!rows.length) return serviceError(404, 'personalTimeRequestNotFound', 'Request not found.');
  const request = rows[0];

  if (!await assertActiveMember(client, request.family_id, userId)) {
    return serviceError(403, 'familyNotMember', 'Not a family member.');
  }
  if (request.status !== 'pending') {
    return serviceError(409, 'personalTimeRequestAlreadySettled', `This request is already ${request.status}.`, { status: request.status });
  }
  if (Number(request.requester_id) === Number(userId)) {
    return serviceError(403, 'personalTimeWithdrawInsteadOfDecline', 'Withdraw your own request instead of declining it.');
  }
  if (request.requested_of && Number(request.requested_of) !== Number(userId)) {
    return serviceError(403, 'personalTimeAddressedToOther', 'This request was addressed to someone else.');
  }

  await refundEscrow(client, request);
  await client.query(
    `UPDATE personal_time_requests
     SET status = 'declined', responded_by = $1, responded_at = $2::timestamptz
     WHERE id = $3`,
    [userId, now.toISOString(), request.id]
  );
  return { data: { declined: true }, request };
}

export async function cancelRequest(client, userId, requestId) {
  const { rows } = await client.query(
    'SELECT * FROM personal_time_requests WHERE id = $1 FOR UPDATE',
    [requestId]
  );
  if (!rows.length) return serviceError(404, 'personalTimeRequestNotFound', 'Request not found.');
  const request = rows[0];

  if (Number(request.requester_id) !== Number(userId)) {
    return serviceError(403, 'personalTimeWithdrawOwnerOnly', 'Only the person who asked can withdraw a request.');
  }
  if (request.status !== 'pending') {
    return serviceError(409, 'personalTimeRequestAlreadySettled', `This request is already ${request.status}.`, { status: request.status });
  }

  await refundEscrow(client, request);
  await client.query(
    `UPDATE personal_time_requests SET status = 'cancelled' WHERE id = $1`,
    [request.id]
  );
  return { data: { cancelled: true }, request };
}

