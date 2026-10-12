import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth } from '../db/users.js';
import { validateBody, required, string } from '../middleware/validate.js';
import { sendError } from '../utils/httpError.js';

export const eventsRouter = Router();

// Whitelisted onboarding instrumentation events (Phase 4 of
// docs/onboarding-help-plan.md). Anything else is rejected so the table
// can't be used as a free-form dumping ground.
const ALLOWED_EVENTS = [
  'welcome_choice',
  'tour_completed',
  'tour_skipped',
  'checklist_step_tapped',
  'checklist_dismissed',
  'checklist_completed',
];

const MAX_DETAIL_BYTES = 1024;

// ─────────────────────────────────────────────
// POST /api/events  { event, detail? }
// Records one onboarding event for the authenticated user.
// ─────────────────────────────────────────────
eventsRouter.post('/', validateBody({
  event: [required(), string(1, 64)],
}), async (req, res) => {
  const { event, detail } = req.body;
  if (!ALLOWED_EVENTS.includes(event)) {
    return sendError(res, 400, 'eventUnknown', 'Unknown event.');
  }
  let detailJson = null;
  if (detail !== undefined && detail !== null) {
    if (typeof detail !== 'object' || Array.isArray(detail)) {
      return sendError(res, 400, 'eventDetailNotObject', 'detail must be an object.');
    }
    detailJson = JSON.stringify(detail);
    if (detailJson.length > MAX_DETAIL_BYTES) {
      return sendError(res, 400, 'eventDetailTooLarge', 'detail too large.');
    }
  }

  try {
    await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      await client.query(
        `INSERT INTO onboarding_events (user_id, event, detail)
         VALUES ($1, $2, $3)`,
        [user.id, event, detailJson]
      );
    });
    res.status(204).end();
  } catch (err) {
    console.error('Failed to record onboarding event:', err);
    sendError(res, 500, 'internal', 'Failed to record event.');
  }
});
