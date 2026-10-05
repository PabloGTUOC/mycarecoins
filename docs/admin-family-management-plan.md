# Platform Admin, Family Registry & Subscriptions — Plan

> **Status: all phases implemented** (see §5 Implementation log). Remaining
> work is external store configuration + on-device sandbox testing (§5
> Phase 4 → "What remains outside the repo").
> Companion docs: `docs/backend.md`, `docs/database-schema.md`, `docs/PRODUCT.md`.
>
> Decisions locked in this revision:
> 1. **Privacy boundary** — the platform admin never sees or touches family internals
>    (members' identities, activities, coins, rewards). Admin scope = family *registry*
>    (is it alive?) + *subscription* (what plan, is it paid?).
> 2. **Payment provider** — **RevenueCat** for App Store + Google Play, kept behind our
>    own webhook boundary so the provider is swappable (Adapty/Qonversion/DIY/Stripe-web
>    later) without touching the data model, admin area, or enforcement.

---

## 1. Current state and gap

All management in CareCoins today is family-scoped self-service: caregivers invite
members, approve joins, change roles, manage actors, and delete their family via
unanimous approval. There is **no platform-level admin at any layer**:

- `users` has no global role; the only roles are `caregiver`/`member` in
  `family_members`. Every "admin" string in the codebase is the `firebase-admin` SDK.
- No code path crosses families — every route resolves through the requester's own
  membership.
- No `/api/admin/*` router, no admin UI in the Flutter app.
- No plan/subscription/payment concept anywhere. `families.monthly_coin_budget` is the
  only plan-like config, derived from actors and read-only via API.

Assets that make this cheap to close: the service-layer pattern
(`familyService`/`memberService`), the `requireRole` middleware to mirror,
`validateBody/Params`, the `scripts/migrate-*.sql` convention, `node --test` service tests,
and per-user rate limiting already wired in `app.js`.

---

## 2. Design principles

**Admin is the landlord, not a housemate.** Families are tenants; what happens inside
is theirs. The admin's two legitimate interests:

1. **Operational** — is this family alive, or abandoned data to eventually clean up?
2. **Commercial** — what plan is the family on, is it paid, what is it entitled to?

Both are served with **aggregates and lifecycle state only**:

- Admin sees per family: id, name, created date, member *count*, heartbeat bucket,
  plan/subscription state. Never member identities, activities, balances, or rewards.
- Admin never deletes family data. Strongest admin power is **suspension**
  (read-only mode); deletion stays exclusively with caregivers via the existing
  unanimous flow. Dormant-family cleanup is a *process* admin triggers (notice →
  waiting period → automated retention deletion), not a button that reads or removes
  data directly.
- The boundary is technical, not aspirational: the admin service queries an explicit
  allowlist of columns, and a CI test asserts admin responses contain no member/content
  fields.

**The backend is the single source of truth for entitlements.** Subscriptions are
per-*family*, but stores sell to a *person* (Apple ID / Google account). The only way
an Android caregiver benefits from an iOS purchase is if clients always ask *our* API
"what plan is my family on?" — never the store, never the RevenueCat SDK cache.
Clients never write entitlements; purchases are evidence the backend verifies
server-side (via RevenueCat) before anything changes.

---

## 3. Target architecture

### 3.1 Platform admin identity

- `users.platform_role` (`'user'` default, `'admin'`), promoted **only** via a CLI
  script — never self-service, never from the client.
- `requireAdmin` middleware in `src/middleware/rbac.js`, same shape as `requireRole`,
  checking the DB (authoritative; Firebase custom claims optional later as
  defense-in-depth).
- Mounted as `app.use('/api/admin', requireAuth, requireAdmin, adminLimiter, adminRouter)`
  with a stricter rate limit than user routes.
- `admin_audit_log` — one row per mutating admin call, written in the same transaction.

### 3.2 Family heartbeat ("is it active?")

Explicit heartbeat column rather than derived queries, so the admin API physically
never touches content tables:

- `families.last_active_at TIMESTAMPTZ` — touched by a tiny middleware on any
  authenticated family-scoped request, throttled to at most one write per family per
  hour. Backfilled once at migration time from existing timestamps, then never derived
  again.
- Server-side buckets: **active** (≤ 30 days), **dormant** (30–90), **inactive** (> 90,
  retention candidate).

### 3.3 Subscription data model

```sql
CREATE TABLE plans (
  code TEXT PRIMARY KEY,               -- 'free', 'plus', …
  name TEXT NOT NULL,
  price_cents INTEGER NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'EUR',
  billing_period TEXT NOT NULL DEFAULT 'monthly',
  limits JSONB NOT NULL DEFAULT '{}',  -- max_members, max_actors, max_active_rewards…
  features JSONB NOT NULL DEFAULT '{}',
  is_default BOOLEAN NOT NULL DEFAULT false,
  active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE family_plans (
  family_id BIGINT PRIMARY KEY REFERENCES families(id) ON DELETE CASCADE,
  plan_code TEXT NOT NULL REFERENCES plans(code),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN
    ('trialing','active','in_grace','past_due','paused','canceled','expired')),
  current_period_end TIMESTAMPTZ,
  platform TEXT,                       -- 'app_store' | 'play' | (future: 'stripe')
  provider TEXT,                       -- 'revenuecat' | 'admin' | (future others)
  provider_subscription_id TEXT,       -- RC subscriber / store transaction reference
  billing_owner_user_id BIGINT REFERENCES users(id),  -- whose store account pays
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE billing_events (          -- raw webhook log: idempotency + debugging
  id BIGSERIAL PRIMARY KEY,
  provider TEXT NOT NULL,
  event_id TEXT UNIQUE,                -- provider's id, dedupes replays
  event_type TEXT NOT NULL,
  family_id BIGINT REFERENCES families(id) ON DELETE SET NULL,
  payload JSONB NOT NULL,
  processed BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE admin_grants (            -- comps/trials: separate from store truth
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  plan_code TEXT NOT NULL REFERENCES plans(code),
  granted_by BIGINT NOT NULL REFERENCES users(id),
  reason TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

- Every family gets the seeded `free` plan on creation (backfill existing families).
- **Effective entitlement = most generous of (store subscription, active admin grant).**
  Store truth and admin truth never overwrite each other: an admin comp is not a fake
  subscription, and an `EXPIRATION` webhook can't wipe a comp.

### 3.4 Purchase & lifecycle flow (RevenueCat)

Store rule that shapes everything: digital-feature subscriptions **must** go through
StoreKit / Play Billing inside the apps. RevenueCat sits on top of both and gives us
one SDK + one normalized webhook stream.

**Purchase (happy path):**

1. Caregiver taps *Upgrade* in the Flutter app. App asks the backend to mint a
   **purchase intent** (UUID → `{user_id, family_id}`), solving family attribution —
   a user may belong to several families.
2. App configures the RevenueCat SDK (`purchases_flutter`) with
   `appUserID = <backend user id>` and attaches the intent UUID as a subscriber
   attribute, then launches the native purchase.
3. RevenueCat validates the receipt with Apple/Google and fires our webhook.
   The handler resolves intent → family, writes `billing_events`, then upserts
   `family_plans` (`active`, period end, platform, billing owner).
4. Every member on every platform gets the entitlement from our API on the next
   request. As immediate UX feedback the app may also POST the RC customer-info to a
   `/api/billing/sync` endpoint, but the webhook remains authoritative.

**Lifecycle:** renewals, cancellations, refunds, billing issues all happen *without
the app* — RevenueCat webhooks (`INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`,
`EXPIRATION`, `BILLING_ISSUE`, `PRODUCT_CHANGE`, `TRANSFER`) arrive at
`/api/billing/webhook` (shared-secret header auth), are logged idempotently in
`billing_events` (webhooks can duplicate or arrive out of order), and are mapped to
our status vocabulary. Grace periods (`in_grace`, Android `paused`) do **not** cut
access.

**Enforcement (system, never admin):**

- `getFamilyEntitlements(client, familyId)` merges plan limits; called at the natural
  choke points: member approve/join, actor add, reward create. Rollout: soft warnings
  first (like the existing `budget_exceeded` pattern), hard limits once plans are live.
- Lapsed subscription ⇒ family enters **read-only mode**: a gate on family-scoped
  write routes returns a clear "subscription inactive" error. Data untouched;
  reactivation instantly restores function.
- Double-purchase guard: if a family already has an active subscription bought on the
  other platform, the app shows "already subscribed via <store> — manage it there"
  instead of a second checkout. Only our backend can know this; the stores can't.

**Admin's role in billing:** view plan, status, platform, renewal date, and
`billing_events` history per family; CRUD the plan catalog; issue/revoke
`admin_grants`. Admin **cannot** cancel or refund store subscriptions — that
relationship belongs to the user and Apple/Google; refunds made in App Store
Connect / Play Console flow back as ordinary webhook events. The console deep-links
to the store consoles rather than pretending to own that lever.

**Provider swappability:** the Flutter purchase trigger and the webhook consumer are
the only RevenueCat-aware components. `family_plans`/`billing_events`/entitlements/
admin area are provider-neutral (`provider` is a column). RevenueCat is free below
$2.5K monthly tracked revenue, then 1% of gross MTR — acceptable at this project's
scale, and revisitable precisely because of this boundary. A future web checkout
(Stripe) becomes a third writer into the same tables; store rules only constrain
purchases inside the apps.

---

## 4. Development phases

### Phase 1 — Platform admin foundation (backend) · S (1–2 days) · ✅ DONE

**Deliverables**
- `scripts/migrate-platform-admin.sql`: `users.platform_role` + `admin_audit_log`;
  mirror into `schema.sql`.
- `scripts/promote-admin.js <email>` promotion script.
- `requireAdmin` in `src/middleware/rbac.js`; `/api/admin` mount in `app.js` with
  dedicated stricter rate limiter; empty `src/routes/admin.js` +
  `src/services/adminService.js` skeleton.
- Audit helper: one `admin_audit_log` row per mutating admin call, same transaction.

**Acceptance**
- Non-admin (and unauthenticated) requests to any `/api/admin/*` route → 403/401,
  covered by tests. Promotion works only via script.

### Phase 2 — Family registry & heartbeat · M (2–3 days) · ✅ DONE

**Deliverables**
- `scripts/migrate-heartbeat.sql`: `families.last_active_at` + one-time backfill from
  existing timestamps.
- Heartbeat middleware on family-scoped routes (throttled ≥ 1 h per family).
- `GET /api/admin/families?search=&status=&page=` — id, name, created_at, member
  count, heartbeat bucket, plan summary. Paged.
- `GET /api/admin/families/:id` — same fields + plan/billing history. **No member
  identities, no content.**
- `POST /api/admin/families/:id/notify-inactive` — sends the inactivity notice through
  existing notify/mailer utilities without exposing addresses to the admin; audited.
- **Leak-prevention test**: asserts registry responses contain only the allowlisted
  fields (fails CI if someone joins content tables later).

**Acceptance**
- Admin can answer "which families are active/dormant/inactive?" with zero access to
  family internals; heartbeat updates cost ≤ 1 write/family/hour.

### Phase 3 — Plans & entitlements (provider-agnostic core) · M (3–4 days) · ✅ DONE

**Deliverables**
- `scripts/migrate-plans.sql`: `plans`, `family_plans`, `billing_events`,
  `admin_grants`; seed `free` default; assign in `familyService.createFamily`;
  backfill existing families.
- `getFamilyEntitlements` helper + soft enforcement at member approve/join, actor
  add, reward create (warning payloads, `budget_exceeded`-style).
- Read-only suspension gate for lapsed families on family-scoped write routes.
- Admin API: `GET/POST/PATCH /api/admin/plans`, `GET /api/admin/families/:id/billing`,
  `POST/DELETE /api/admin/families/:id/grants`.
- Tests: entitlement merge (store vs grant, most generous wins), suspension gate,
  plan CRUD, grants.

**Acceptance**
- System is fully plan-aware with zero payment code; a comp'd family and a free
  family behave per their limits; suspended family is read-only and instantly
  restorable.

### Phase 4 — RevenueCat integration · M (3–5 days + store admin lead time) · ✅ DONE (code)

**Deliverables**
- Store setup (external to repo, start early — review/config lead time):
  subscription products in App Store Connect + Play Console, RevenueCat project,
  entitlement (`premium`), offerings, webhook + shared secret.
- Backend: `POST /api/billing/webhook` (secret-header auth, idempotent via
  `billing_events.event_id`, event→status mapping incl. grace/paused);
  `POST /api/billing/purchase-intent`; optional `POST /api/billing/sync`.
- Flutter: `purchases_flutter` SDK; upgrade/paywall flow on the family screen
  (caregivers only); `appUserID` = backend user id + intent attribute;
  double-purchase guard; "manage subscription" deep links to store subscription
  settings; l10n via existing `.arb` files.
- Entitlement enforcement flips from soft to hard for store-driven plans.
- Sandbox test matrix: purchase, renewal, cancel, expiration, billing issue/grace,
  cross-platform visibility (buy on iOS sandbox → Android member sees premium).

**Acceptance**
- One caregiver's purchase upgrades the whole family on both platforms within one
  webhook delivery; cancellation downgrades at period end, not immediately; replayed
  webhooks are no-ops.

### Phase 5 — Admin UI (Flutter) · M (3–4 days) · ✅ DONE

**Deliverables**
- `/api/me` returns `platformRole`; Admin entry in shell/profile only for admins
  (server still enforces; UI gating is convenience).
- Screens: `admin_families_screen` (search + status chips active/dormant/inactive +
  plan badges) → `admin_family_detail_screen` (registry fields, billing history,
  grant/revoke, notify-inactive) → `admin_plans_screen` (catalog CRUD).
- Strings through existing l10n `.arb` files.

**Acceptance**
- Admin can run registry + billing oversight entirely from the app; no screen renders
  family internals.

### Phase 6 — Hardening, retention, docs & store readiness · S (1–2 days) · ✅ DONE

**Deliverables**
- Retention policy for `inactive` families: notice → waiting period → automated
  deletion job (admin triggers the process, system touches the data).
- Consider recent re-auth (Firebase `auth_time`) for destructive admin actions.
- Docs: update `backend.md` (RBAC §, admin router, billing webhook),
  `database-schema.md`, `PRODUCT.md`.
- Store-release checklist additions (now `docs/deployment-and-delivery.md` §6): IAP review
  requirements, subscription disclosures, restore-purchases flow (Apple requires it —
  ours is trivial: entitlements come from the backend).

**Dependencies & sequencing**

| Phase | Depends on | Note |
|---|---|---|
| 1 Foundation | — | |
| 2 Registry | 1 | Closes the operational gap on its own |
| 3 Plans core | 1 | Can run parallel to 2 |
| 4 RevenueCat | 3 | Start store/RC console setup during 3 |
| 5 Admin UI | 2, 3 | Billing panels grow in 4 |
| 6 Hardening | rolling | |

---

## 5. Implementation log (Phases 1–3)

Everything below is implemented on the backend, with the full test suite green
(91 tests). Endpoints all live under `/api/admin` behind
`requireAuth → adminLimiter (100 req/15 min) → requireAdmin`.

### Phase 1 — Platform admin foundation

| Piece | Where |
|---|---|
| `users.platform_role` (`'user'`/`'admin'`) + `admin_audit_log` | `scripts/migrate-platform-admin.sql`, mirrored in `src/db/schema.sql`, chained in `scripts/init-db.js` |
| CLI-only promotion | `node scripts/promote-admin.js <email> [--demote]` — no API path to become admin exists |
| `requireAdmin` middleware + `checkPlatformAdmin` helper | `src/middleware/rbac.js` — DB is authoritative, mirrors `requireRole`'s shape |
| `/api/admin` mount + self-check `GET /api/admin/status` | `src/app.js`, `src/routes/admin.js` |
| `logAdminAction` audit helper | `src/services/adminService.js` — one row per mutating admin call, same transaction |

Design note: platform admin is a **separate axis** from family roles — an
admin gains zero implicit rights inside any family. This is the technical
root of the privacy boundary.

Drive-by fix: `src/utils/mailer.js` constructed the Resend client eagerly at
import, crashing any keyless environment despite having a mock path for
exactly that case. The client is now lazy.

### Phase 2 — Family registry & heartbeat

| Piece | Where |
|---|---|
| `families.last_active_at` + one-time backfill + index | `scripts/migrate-heartbeat.sql` (backfill = greatest of creation, latest activity, ledger entry, member join; then `NOT NULL DEFAULT NOW()`) |
| Heartbeat middleware | `src/middleware/heartbeat.js`, mounted on all family-scoped routers in `app.js` |
| `GET /api/admin/families?search=&status=&page=&pageSize=` | paged registry: id, name, createdAt, lastActiveAt, memberCount, status bucket |
| `GET /api/admin/families/:id` | registry fields + pendingMemberCount + actorCount |
| `POST /api/admin/families/:id/notify-inactive` | nudges caregivers via the existing push utility (`family_events` pref); audited |

Decisions taken during implementation:

- **Success-only heartbeat**: the middleware touches the timestamp on the
  response `finish` event and only for `< 400` status codes — an
  unauthorized probe cannot keep a family looking alive. Throttled
  in-memory to one write per family per hour. Deliberately not mounted on
  `/api/admin`: admin oversight is not family activity.
- Buckets computed server-side: **active** ≤ 30 days, **dormant** 30–90,
  **inactive** > 90.
- **Leak barrier is tested**: `adminService` maps rows through an explicit
  field allowlist, and `tests/adminRegistry.test.js` feeds it rows
  contaminated with emails/aliases/activity titles and asserts only
  registry fields surface. A future query that joins content tables fails CI.

### Phase 3 — Plans & entitlements

| Piece | Where |
|---|---|
| `plans`, `family_plans`, `billing_events`, `admin_grants` + `free` seed + backfill | `scripts/migrate-plans.sql`, mirrored in `schema.sql` |
| Default plan assigned at family creation | `familyService.createFamily` |
| `getFamilyEntitlements` / `limitWarning` / `assertFamilyWritable` | `src/services/entitlementService.js` |
| Soft enforcement choke points | `memberService.approveMember`, `joinByInvitation`, `joinByToken` (`member_limit_exceeded`), `memberService.addActor` (`actor_limit_exceeded`), marketplace reward creation (`reward_limit_exceeded`) |
| Plan catalog API | `GET/POST /api/admin/plans`, `PATCH /api/admin/plans/:code` (audited) |
| Family billing view | `GET /api/admin/families/:id/billing` — subscription state, grants, and event **metadata only** (id/provider/type/processed/time — never raw provider payloads) |
| Grants API | `POST /api/admin/families/:id/grants`, `DELETE …/grants/:grantId` (revocation = `revoked_at` timestamp, never a hard delete; audited) |

Decisions taken during implementation:

- **Entitlement merge, most generous wins**, across three sources: default
  plan (always), subscription plan (only in good standing:
  `trialing`/`active`/`in_grace`), unrevoked+unexpired admin grants.
  Limits: absent key = unlimited for that source, and unlimited from any
  source wins. Features: opposite polarity — ON if any source grants it.
- **Suspension is `past_due` only.** `canceled`/`expired`/`paused`
  subscriptions downgrade gracefully to the default plan — the family
  keeps working at free-tier entitlements. Only unpaid-but-owed
  (`past_due`, i.e. beyond the store grace window) triggers
  `assertFamilyWritable`'s 402 read-only gate, which is called **before**
  mutations at every choke point (`withTransaction` only rolls back on
  throw, so a post-write gate would not undo anything).
- **Soft rollout as planned**: limit breaches attach a `warning` field to
  otherwise-successful responses (`budget_exceeded` pattern). Warnings use
  post-operation counts and fire only strictly over the limit. Hardening
  to rejections is a Phase 4 flip.
- The seeded `free` plan ships with `limits = {}` (= everything
  unlimited), so rollout changes nothing for existing families. Limits
  become real the moment the catalog is edited via
  `PATCH /api/admin/plans/free` — no code change needed.
- Gating the marketplace *redeem* route and activity writes under
  suspension is deferred to Phase 4 hardening, when `past_due` can
  actually occur (nothing sets it until webhooks exist).

### Phase 5 — Flutter admin UI

| Piece | Where |
|---|---|
| `platform_role` in `/api/me` | `upsertUserFromAuth` RETURNING clauses (`src/db/users.js`) — flows through automatically |
| Gated entry | Profile → Account Settings shows an "Admin console" row only when `AppState.isPlatformAdmin`; UI gating only, server re-checks every call |
| Console | `fluterFront/lib/screens/admin_screen.dart`: `AdminScreen` (Families / Plans tabs), `AdminFamilyDetailScreen` |
| Families tab | search, status filter (all/active/dormant/inactive), status + plan pills, pagination ("load more") |
| Family detail | registry card (created, heartbeat, counts, notify-inactive with confirm), billing card, grants card (grant dialog: plan dropdown + reason + expiry-in-days; revoke), billing-event metadata list |
| Plans tab | catalog list with default/inactive badges, create/edit dialog (name, price cents, period, per-key limits where empty = unlimited, default/active switches) |
| l10n | 58 keys added to all four `.arb` files (en/es/fr/de) |
| Registry API addition | list/detail now also return `planCode` + `subscriptionStatus` (registry-safe) for the plan badges; leak-test allowlist updated |

The console renders registry and billing state only — there is deliberately
no screen that shows members, tasks or coins, mirroring the API boundary.

### Phase 6 — Hardening, retention & docs

| Piece | Where |
|---|---|
| Retention sweep | `src/services/retentionService.js` + `scripts/retention-sweep.js` — dry-run by default, `--apply` to delete; candidates need BOTH `last_active_at` older than `--inactive-days` (365) AND a `family.notify_inactive` audit entry older than `--notice-days` (30); the DELETE re-verifies inactivity so a returning family is skipped; audited as the admin whose notice started the process |
| Re-auth plumbing | `req.auth.authTime` (Firebase `auth_time`) now available for future recent-login guards |
| Docs | `backend.md` §18 (operational reference), `database-schema.md` (5 new tables, 2 new columns, 4 new indexes), `PRODUCT.md` feature §13, `deployment-and-delivery.md` §6 (Phase 4 IAP prep checklist) |
| Tests | `tests/retention.test.js` |

Decision on **re-auth for destructive admin actions**: deferred, deliberately.
No admin API endpoint is destructive today — the strongest API powers are
grant revocation and the (audited) inactivity notice; retention deletion runs
via an operator CLI that already requires server access. `req.auth.authTime`
is plumbed so a recent-login guard is a five-line middleware when Phase 4
adds anything sharper.

### Phase 4 — RevenueCat integration

| Piece | Where |
|---|---|
| Webhook consumer | `POST /api/billing/webhook` (`src/routes/billing.js` + `src/services/billingService.js`): shared-secret auth (`REVENUECAT_WEBHOOK_SECRET`), idempotent via `billing_events.event_id`, event→status normalization, `family_plans` upsert; plan row auto-created on first sight and curated later via the admin plan API |
| Family entitlements endpoint | `GET /api/families/:id/entitlements` — member-accessible single source of truth for clients (plan, status, platform, period end, limits, features, `subscribed`) |
| Flutter SDK | `purchases_flutter` + `purchases_ui_flutter` (^9); `lib/services/purchase_service.dart` — configure with per-platform keys (`--dart-define=RC_IOS_KEY/RC_ANDROID_KEY`, test-store key as dev default), `logIn` with the backend user id after auth, `logOut` on sign-out |
| Purchase flow | `SubscriptionCard` in Account Settings: backend-driven Pro state, caregiver-only Upgrade → sets the `family_id` subscriber attribute → RevenueCat Paywall (`presentPaywallIfNeeded('MyCareCoins Pro')`) → polls the backend until the webhook lands; Manage → RevenueCat Customer Center; Restore purchases (Apple-required); hides on web |
| Double-purchase guard | Backend `platform` on the subscription + client check: already subscribed via the other store → "managed on X" message instead of a second checkout |
| Tests | `tests/billing.test.js` (idempotency, attribution, lifecycle mapping, lifetime) + canceled-until-period-end case in `tests/entitlements.test.js` |

Decisions taken during implementation:

- **Subscriber attribute replaced the purchase-intent endpoint.** The
  planned mint-an-intent-UUID flow existed to attribute a store purchase to
  a family; setting a `family_id` subscriber attribute just before the
  paywall achieves the same attribution with one moving part instead of
  three (endpoint + storage + expiry). The webhook treats an event without
  the attribute as unprocessed rather than guessing.
- **RevenueCat Paywall UI + Customer Center adopted** instead of a fully
  custom paywall — it is the SDK's modern path and halves the UI work. Our
  wrapper still owns what RevenueCat cannot know: the family-level
  double-purchase guard before presenting, and backend confirmation
  polling after purchasing.
- **Cancellation keeps benefits until period end** (entitlementService
  change): the user paid through the period; the later EXPIRATION webhook
  performs the actual downgrade. `BILLING_ISSUE` maps to `in_grace`;
  `past_due` stays reserved for a future explicit dunning state, so the
  402 read-only gate remains dormant until deliberately used.
- **Products** (`monthly`, `yearly`, `lifetime`) all attach to the single
  RevenueCat entitlement `MyCareCoins Pro`, which maps to plan code `pro`.
  Lifetime arrives as `NON_RENEWING_PURCHASE` → active with no period end.
- **Hard limits stay soft for now.** Warnings still flow (Phase 3); the
  hard flip needs the limit check moved before the mutation at each choke
  point, which is a contained follow-up once real plan limits exist in the
  catalog.

**What remains outside the repo** (operator checklist, see also
`docs/deployment-and-delivery.md` §6):

1. App Store Connect + Play Console: create the three subscription
   products; attach store credentials in RevenueCat.
2. RevenueCat dashboard: attach products to the `MyCareCoins Pro`
   entitlement, default offering (+ optional hosted paywall design),
   webhook → `https://mycarecoins.app/api/billing/webhook` with the
   Authorization value mirrored into `REVENUECAT_WEBHOOK_SECRET`.
3. Local build: `flutter pub get`, `flutter analyze`, then the sandbox
   matrix (purchase / renewal / cancel / expiration / grace /
   cross-platform visibility). Release builds pass the real public SDK
   keys via `--dart-define=RC_IOS_KEY=appl_… RC_ANDROID_KEY=goog_…`.

---

## 6. Out of scope / related product task

- **Orphaned families** (sole caregiver leaves/demotes): under the privacy boundary
  admin cannot fix this by editing roles. Solve it inside the product instead — block
  the last active caregiver from leaving or demoting without first transferring the
  role. Small, independent task; recommended before or alongside Phase 2.
- Web checkout (Stripe), Firebase custom-claim mirroring, separate web admin panel:
  all deliberately deferred; the data model already leaves room for each.
