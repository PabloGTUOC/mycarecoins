/**
 * RevenueCat webhook processing (docs/admin-family-management-plan.md
 * Phase 4).
 *
 * The backend is the single source of truth for entitlements: RevenueCat
 * validates receipts with Apple/Google and pushes lifecycle events here;
 * this module normalizes them into family_plans. Clients never write
 * entitlements — a purchase on-device is only evidence.
 *
 * Family attribution: subscriptions are per-family but stores sell to a
 * person, so the app sets a `family_id` subscriber attribute before the
 * purchase (PurchaseService.presentPaywall). Events without it are logged
 * to billing_events with processed = false for manual follow-up — they can
 * be replayed once attributed.
 *
 * Idempotency: billing_events.event_id is UNIQUE; a replayed event is
 * acknowledged without reprocessing.
 */
// RevenueCat entitlement identifier → our plan catalog code. The plan row
// is created on first sight (ON CONFLICT DO NOTHING) so a webhook never
// fails on FK; price/limits are then curated via the admin plan API.
import { serviceError } from '../utils/httpError.js';

const ENTITLEMENT_PLAN_MAP = { 'MyCareCoins Pro': 'pro' };
const DEFAULT_PAID_PLAN = 'pro';

// Event → subscription status. Semantics (plan §3.3/§3.4):
// - CANCELLATION means auto-renew was turned off; the family stays entitled
//   until current_period_end (handled in entitlementService), and the later
//   EXPIRATION event flips to 'expired'.
// - BILLING_ISSUE maps to in_grace (still entitled) until the store gives
//   up and sends EXPIRATION.
// - NON_RENEWING_PURCHASE is the lifetime product: active, no period end.
const STATUS_BY_EVENT = {
  INITIAL_PURCHASE: 'active',
  RENEWAL: 'active',
  UNCANCELLATION: 'active',
  PRODUCT_CHANGE: 'active',
  TRANSFER: 'active',
  NON_RENEWING_PURCHASE: 'active',
  CANCELLATION: 'canceled',
  EXPIRATION: 'expired',
  BILLING_ISSUE: 'in_grace',
  SUBSCRIPTION_PAUSED: 'paused',
};

const PLATFORM_BY_STORE = {
  APP_STORE: 'app_store',
  MAC_APP_STORE: 'app_store',
  PLAY_STORE: 'play',
  STRIPE: 'stripe',
};

function attributedFamilyId(event) {
  const raw = event.subscriber_attributes?.family_id?.value;
  const id = Number(raw);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function planCodeFor(event) {
  const entitlement = event.entitlement_ids?.[0] ?? event.entitlement_id;
  return ENTITLEMENT_PLAN_MAP[entitlement] ?? DEFAULT_PAID_PLAN;
}

export async function applyStoredEvent(client, eventRow) {
  const event = typeof eventRow.payload === 'string'
    ? JSON.parse(eventRow.payload)
    : (eventRow.payload || {});
  const eventId = eventRow.event_id || event.id;

  if (event.store === 'PROMOTIONAL') {
    await client.query(
      `UPDATE billing_events SET processed = true WHERE event_id = $1`, [eventId]);
    return {
      data: { ignored: 'promotional_mirror' },
      processed: true,
      outcome: 'promotional_mirror',
    };
  }

  const status = STATUS_BY_EVENT[event.type];
  if (!status) {
    // Informational event (e.g. SUBSCRIPTION_EXTENDED variants we don't
    // model) — keep the log entry, nothing to apply.
    await client.query(
      `UPDATE billing_events SET processed = true WHERE event_id = $1`, [eventId]);
    return {
      data: { ignored: event.type },
      processed: true,
      outcome: 'ignored',
    };
  }

  const familyId = attributedFamilyId(event);
  if (!familyId) {
    return {
      data: { unattributed: true },
      processed: false,
      outcome: 'unattributed',
    };
  }

  const planCode = planCodeFor(event);
  await client.query(
    `INSERT INTO plans (code, name) VALUES ($1, $2) ON CONFLICT (code) DO NOTHING`,
    [planCode, planCode === DEFAULT_PAID_PLAN ? 'MyCareCoins Pro' : planCode]
  );

  const billingOwner = Number(event.app_user_id);
  await client.query(
    `INSERT INTO family_plans
       (family_id, plan_code, status, current_period_end, platform, provider,
        provider_subscription_id, billing_owner_user_id, updated_at)
     VALUES ($1, $2, $3, $4, $5, 'revenuecat', $6, $7, NOW())
     ON CONFLICT (family_id) DO UPDATE SET
       plan_code = EXCLUDED.plan_code,
       status = EXCLUDED.status,
       current_period_end = EXCLUDED.current_period_end,
       platform = EXCLUDED.platform,
       provider = EXCLUDED.provider,
       provider_subscription_id = EXCLUDED.provider_subscription_id,
       billing_owner_user_id = COALESCE(EXCLUDED.billing_owner_user_id, family_plans.billing_owner_user_id),
       updated_at = NOW()`,
    [
      familyId,
      planCode,
      status,
      event.expiration_at_ms ? new Date(Number(event.expiration_at_ms)) : null,
      PLATFORM_BY_STORE[event.store] ?? null,
      event.original_transaction_id ?? event.transaction_id ?? null,
      Number.isInteger(billingOwner) && billingOwner > 0 ? billingOwner : null,
    ]
  );

  await client.query(
    `UPDATE billing_events SET processed = true, family_id = $2 WHERE event_id = $1`,
    [eventId, familyId]
  );

  return {
    data: { familyId, planCode, status },
    processed: true,
    outcome: 'applied',
  };
}

export async function processWebhookEvent(client, event) {
  if (!event?.type || !event.id) {
    return serviceError(400, 'billingMalformedEvent', 'Malformed event.');
  }

  const familyId = attributedFamilyId(event);
  const { rowCount: inserted } = await client.query(
    `INSERT INTO billing_events (provider, event_id, event_type, family_id, payload)
     VALUES ('revenuecat', $1, $2, $3, $4)
     ON CONFLICT (event_id) DO NOTHING`,
    [event.id, event.type, familyId, JSON.stringify(event)]
  );
  if (!inserted) return { data: { duplicate: true } };

  const result = await applyStoredEvent(client, {
    event_id: event.id,
    event_type: event.type,
    family_id: familyId,
    payload: event,
  });
  return { data: result.data };
}

const APPLIED_EVENT_TYPES = Object.keys(STATUS_BY_EVENT);

export async function reprocessEvent(client, eventId) {
  const numericId = Number(eventId);
  if (!Number.isInteger(numericId) || numericId <= 0) {
    return serviceError(400, 'invalidInput', 'eventId must be a positive integer.');
  }

  const { rows } = await client.query(
    `SELECT id, event_id, event_type, family_id, payload, processed, created_at
     FROM billing_events
     WHERE id = $1
     FOR UPDATE`,
    [numericId]
  );
  if (!rows.length) {
    return serviceError(404, 'notFound', 'Billing event not found.');
  }

  const row = rows[0];
  if (row.processed) {
    return serviceError(409, 'reprocessAlreadyProcessed', 'This event was already applied.');
  }

  const payload = typeof row.payload === 'string'
    ? JSON.parse(row.payload)
    : (row.payload || {});
  const familyId = attributedFamilyId(payload);

  if (familyId) {
    const rawTimestamp = payload.event_timestamp_ms;
    const eventTimestampMs = rawTimestamp != null && String(rawTimestamp).trim() !== ''
      ? Number(rawTimestamp)
      : null;

    // Only events that changed family_plans count as "newer": mirror
    // (PROMOTIONAL) and informational events are processed too, but never
    // applied, so they must not make a real event stale.
    let newerQuery;
    let newerParams;

    if (Number.isFinite(eventTimestampMs)) {
      newerQuery = `SELECT id FROM billing_events
       WHERE family_id = $1
         AND processed = true
         AND event_type = ANY($3)
         AND COALESCE(payload->>'store', '') <> 'PROMOTIONAL'
         AND (payload->>'event_timestamp_ms')::bigint > $2
       LIMIT 1`;
      newerParams = [familyId, eventTimestampMs, APPLIED_EVENT_TYPES];
    } else {
      newerQuery = `SELECT id FROM billing_events
       WHERE family_id = $1
         AND processed = true
         AND event_type = ANY($3)
         AND COALESCE(payload->>'store', '') <> 'PROMOTIONAL'
         AND created_at > $2
       LIMIT 1`;
      newerParams = [familyId, row.created_at || new Date(), APPLIED_EVENT_TYPES];
    }

    const { rows: newerRows } = await client.query(newerQuery, newerParams);
    if (newerRows.length > 0) {
      await client.query(
        `UPDATE billing_events SET processed = true, family_id = $2 WHERE id = $1`,
        [row.id, familyId]
      );
      return {
        data: {
          processed: true,
          outcome: 'stale',
        },
      };
    }
  }

  const result = await applyStoredEvent(client, row);
  return {
    data: {
      processed: result.processed,
      outcome: result.outcome,
    },
  };
}
