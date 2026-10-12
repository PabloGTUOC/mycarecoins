/**
 * Billing webhooks (docs/admin-family-management-plan.md Phase 4).
 *
 * Mounted WITHOUT requireAuth — RevenueCat is the caller, authenticated by
 * the shared secret configured as the webhook's Authorization header in the
 * RevenueCat dashboard and mirrored in REVENUECAT_WEBHOOK_SECRET. Both the
 * raw value and the "Bearer <value>" form are accepted.
 *
 * Response contract (RevenueCat retries on non-2xx):
 *   401 bad/missing secret · 400 malformed body ·
 *   200 processed, duplicate, or deliberately skipped · 500 transient
 */
import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { processWebhookEvent } from '../services/billingService.js';
import { sendServiceError, sendError } from '../utils/httpError.js';

export const billingRouter = Router();

billingRouter.post('/webhook', async (req, res) => {
  const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
  const header = req.headers.authorization || '';
  if (!secret || (header !== secret && header !== `Bearer ${secret}`)) {
    return sendError(res, 401, 'billingUnauthorized', 'Unauthorized.');
  }

  const event = req.body?.event;
  if (!event) return sendError(res, 400, 'billingMissingEvent', 'Missing event.');

  try {
    const result = await withTransaction((client) => processWebhookEvent(client, event));
    if (result.error) return sendServiceError(res, result.error);
    if (result.data.unattributed) {
      // Logged for follow-up; 200 so RevenueCat doesn't retry forever.
      console.warn(`RevenueCat event ${event.id} (${event.type}) has no family_id attribute.`);
    }
    return res.json({ ok: true });
  } catch (err) {
    console.error('RevenueCat webhook processing failed:', err);
    return sendError(res, 500, 'internal', 'Webhook processing failed.');
  }
});
