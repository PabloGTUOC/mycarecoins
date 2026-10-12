import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth } from '../db/users.js';
import { validateBody, validateParams, required, string, positiveInt, isoDate, oneOf } from '../middleware/validate.js';
import { notifyUser, notifyFamilyCaregivers } from '../utils/notify.js';
import * as personalTime from '../services/personalTimeService.js';
import { sendServiceError, sendError } from '../utils/httpError.js';

export const personalTimeRouter = Router();

const PREF = 'coverage_requests';

const when = (iso) => new Date(iso).toLocaleString('en-US', {
  month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
});

/** Tells whoever has to answer that a request is waiting. */
function announce(request) {
  const payload = {
    title: 'Someone asked you to cover',
    body: `"${request.title}" on ${when(request.starts_at)}.`,
    url: '/dashboard',
    prefKey: PREF,
  };
  if (request.requested_of) notifyUser(request.requested_of, payload);
  else notifyFamilyCaregivers(request.family_id, request.requester_id, payload);
}

// GET /api/personal-time?familyId=X
personalTimeRouter.get('/', async (req, res) => {
  const familyId = Number(req.query.familyId);
  if (!familyId) return sendError(res, 400, 'familyIdRequired', 'familyId query param is required.');
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return personalTime.listRequests(client, user.id, familyId);
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error('GET /personal-time error:', err);
    return sendError(res, 500, 'internal', 'Failed to fetch requests.');
  }
});

// POST /api/personal-time/quote — price a window before committing to it.
personalTimeRouter.post('/quote', validateBody({
  familyId: [required(), positiveInt()],
  startsAt: [required(), isoDate()],
  endsAt: [required(), isoDate()],
  recurrence: [oneOf(personalTime.RECURRENCES)],
  recurrenceUntil: [isoDate()],
}), async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return personalTime.quoteRequest(client, user.id, req.body);
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error('POST /personal-time/quote error:', err);
    return sendError(res, 500, 'internal', 'Failed to price this window.');
  }
});

// POST /api/personal-time — ask for the time, escrowing any sweetener.
personalTimeRouter.post('/', validateBody({
  familyId: [required(), positiveInt()],
  title: [required(), string(1, 100)],
  type: [required(), oneOf(personalTime.SELF_TYPES)],
  description: [string(0, 500)],
  startsAt: [required(), isoDate()],
  endsAt: [required(), isoDate()],
  recurrence: [oneOf(personalTime.RECURRENCES)],
  recurrenceUntil: [isoDate()],
}), async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return personalTime.createRequest(client, user.id, req.body);
    });
    if (result.error) return sendServiceError(res, result.error);
    if (result.data.status === 'pending') announce(result.data);
    return res.status(201).json({ request: result.data, warnings: result.warnings });
  } catch (err) {
    console.error('POST /personal-time error:', err);
    return sendError(res, 500, 'internal', 'Failed to create the request.');
  }
});

// POST /api/personal-time/:id/accept — book the pair.
personalTimeRouter.post('/:id/accept', validateParams('id'), async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return personalTime.acceptRequest(client, user.id, Number(req.params.id));
    });
    if (result.error) return sendServiceError(res, result.error);
    const { created, skipped } = result.data;
    notifyUser(result.request.requester_id, {
      title: 'Your personal time is covered',
      body: created > 1
        ? `"${result.request.title}" was accepted — ${created} of ${created + skipped} times.`
        : `"${result.request.title}" on ${when(result.request.starts_at)} was accepted.`,
      url: '/daily',
      prefKey: PREF,
    });
    return res.status(201).json(result.data);
  } catch (err) {
    console.error('POST /personal-time/accept error:', err);
    return sendError(res, 500, 'internal', 'Failed to accept the request.');
  }
});

// POST /api/personal-time/:id/decline — refund and tell them.
personalTimeRouter.post('/:id/decline', validateParams('id'), async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return personalTime.declineRequest(client, user.id, Number(req.params.id));
    });
    if (result.error) return sendServiceError(res, result.error);
    notifyUser(result.request.requester_id, {
      title: 'Personal time declined',
      body: `Nobody can cover "${result.request.title}" on ${when(result.request.starts_at)}.`,
      url: '/dashboard',
      prefKey: PREF,
    });
    return res.json(result.data);
  } catch (err) {
    console.error('POST /personal-time/decline error:', err);
    return sendError(res, 500, 'internal', 'Failed to decline the request.');
  }
});

// DELETE /api/personal-time/:id — the requester withdraws.
personalTimeRouter.delete('/:id', validateParams('id'), async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return personalTime.cancelRequest(client, user.id, Number(req.params.id));
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error('DELETE /personal-time error:', err);
    return sendError(res, 500, 'internal', 'Failed to withdraw the request.');
  }
});
