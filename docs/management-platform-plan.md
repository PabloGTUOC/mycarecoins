# Management Platform (Operator Console) — Plan

> **Status: Phase 1 in progress** (2026-10-15). Phase 0 research done; console setup (keys,
> tunnel) still with the owner and runs in parallel.
> Supersedes the *placement* of the admin console from
> `docs/admin-family-management-plan.md` Phase 5. That plan's data model, privacy boundary,
> webhook and entitlement rules stay as they are; this plan moves the console out of the
> subscriber app.
> Companion docs: `docs/admin-family-management-plan.md`, `docs/RevenueCatSetup.md`,
> `docs/deployment-and-delivery.md`, `docs/backend.md`.
>
> Decisions taken (owner, 2026-10-15):
> 1. **One frontend stack.** The console is a separate Flutter **web** app.
> 2. **Same host, separate containers.** The console and its API run next to the existing
>    stack on the production server, each in its own container.
> 3. **Its own subdomain.** The console is reached only at `admin.mycarecoins.app`.
> 4. **Free plans show up in RevenueCat.** Every plan the operator grants is mirrored into
>    RevenueCat, so its dashboards and charts count it.

---

## 1. Why

Today the operator console is a screen inside the subscriber app (`admin_screen.dart`, about
870 lines, gated by `AppState.isPlatformAdmin`), and its API (`/api/admin/*`) is mounted on the
same public backend that every phone talks to. That means:

- Every iOS, Android and web build ships the console code and 58 operator strings in four
  languages. App reviewers and curious users can find it.
- The public API exposes operator endpoints. They are protected by `requireAdmin`, but they
  exist, and one middleware mistake would open them.
- `/api/me` tells every user their `platform_role`.
- The console can only use what the public backend has. Managing RevenueCat and App Store
  Connect needs **secret** keys, and the public backend should never hold them.

**Goal:** a subscriber's app, network traffic and API contain nothing about operating the
platform. The operator gets a console that manages subscriptions, the plan catalogue, free plans,
RevenueCat and the App Store from one place.

**Non-goals:**
- The operator still sees no family content. The landlord rule from
  `admin-family-management-plan.md` §2 still holds: registry and billing only.
- No refunds or cancellations from the console. Those belong to Apple, Google and the user; the
  console links out to them.
- No web checkout (Stripe). That stays a later, separate decision.

---

## 2. Target architecture

```
                                  Cloudflare
                 ┌────────────────────┴─────────────────────┐
        mycarecoins.app                            admin.mycarecoins.app
        DNS → server :80                           Cloudflare Tunnel + Access
                 │                                 (no open port on the server)
                 │                                          │
  ┌──────────────┴──────────────┐      ┌────────────────────┴───────────────────┐
  │ frontend  (nginx)           │      │ cloudflared ──► admin-web  (nginx)     │
  │ Flutter app, no admin code  │      │                 Flutter web console    │
  │   /api ─► backend :3000     │      │                 /admin-api ─► admin-api│
  └──────────────┬──────────────┘      └────────────────────┬───────────────────┘
                 │                                          │
  ┌──────────────┴──────────────┐      ┌────────────────────┴───────────────────┐
  │ backend  (public API)       │      │ admin-api  :3001  (operator API)       │
  │ no /api/admin               │      │ RevenueCat secret key                  │
  │ RevenueCat webhook stays    │      │ App Store Connect API key              │
  └──────────────┬──────────────┘      └────────────────────┬───────────────────┘
                 │ role: carecoins (owner)                  │ role: carecoins_admin
                 └──────────────────► postgres ◄────────────┘   (views + billing tables only)
```

Four new pieces:

| Piece | What it is | Where in the repo |
|---|---|---|
| `admin-web` | Flutter web app, desktop only, English only, served by its own nginx | `adminFront/` (new top-level folder, its own `pubspec.yaml`) |
| `admin-api` | Second Express server, built from the `backend/` package with its own entry point | `backend/src/admin/` (`server.js`, `app.js`, routes, RevenueCat and App Store clients) |
| `cloudflared` | Cloudflare Tunnel connector: carries `admin.mycarecoins.app` to `admin-web` without opening a port | `docker-compose.yml` service, token in `admin.env` |
| `carecoins_admin` | Postgres role that can read only the operator views and billing tables | migration + `init-db.js` |

### 2.1 Why these choices

- **Flutter web for the console, but no shared code with the app.** You keep one stack. A
  separate `pubspec.yaml` means the subscriber app cannot import a console file by accident,
  and the console cannot drag app code into its bundle. The console copies the few theme tokens
  it needs; a shared `packages/` folder can come later if duplication starts to hurt.
- **`admin-api` lives in the `backend/` package.** It reuses `adminService`,
  `entitlementService`, `billingService`, `db/`, the audit middleware and the test setup
  (`mockClient`). It is its own process and container with its own env file, so its secrets
  never reach the public backend's environment. The two cannot share an Express app: the
  public `app.js` simply does not import `src/admin/`.
- **A Cloudflare Tunnel instead of a second port.** The `frontend` container already owns
  port 80. A tunnel means the server opens no new port, the console is unreachable except
  through Cloudflare, and Cloudflare Access (free for one user) can sit in front of it. The
  alternative is an edge proxy container that routes by `Host`, which would put the public app
  and the console behind one more shared component.
- **The RevenueCat webhook stays on the public backend.** RevenueCat must be able to reach it
  without passing Cloudflare Access, and it is part of how subscribers get their plan, not an
  operator tool.

### 2.2 Getting into the console: three layers

1. **Cloudflare Access** on `admin.mycarecoins.app`: one policy allowing only the owner's email,
   with a one-time PIN or Google login. Nobody else ever loads the page, not even the sign-in
   screen.
2. **`admin-api` checks the Access token.** Every request must carry a valid
   `Cf-Access-Jwt-Assertion` header, checked against the team's public keys and the
   application's audience tag (`CF_ACCESS_AUD`). This protects against someone reaching the
   container by another route.
3. **Firebase sign-in + `requireAdmin`**, as today: a Firebase ID token for a user whose
   `users.platform_role = 'admin'`. Mutating calls also need a recent sign-in, using the
   `req.auth.authTime` plumbing that already exists (proposed: 30 minutes, see §8).

`admin.mycarecoins.app` is added to the Firebase Auth authorised domains. Admins are still
created only with `node backend/scripts/promote-admin.js <email>`.

### 2.3 The data boundary, enforced by the database

Today the privacy boundary is code: `adminService` lists columns explicitly and a test checks
the responses. `admin-api` keeps both, and adds a database role that cannot read anything
else:

- **Views owned by the main role.** Postgres runs a view with its owner's rights, so the views
  can count rows the admin role itself cannot read:
  - `admin_family_registry`: family id, name, created_at, last_active_at, heartbeat bucket,
    member count, caregiver count, actor count, plan code, subscription status. These are the
    columns `adminService` already returns.
  - `admin_billing_owner`: family id and billing-owner user id only (no email, no name), for
    linking RevenueCat customers.
- **Grants for `carecoins_admin`:**
  - `SELECT` on those views, plus `plans`, `family_plans`, `billing_events`, `admin_grants`,
    `admin_audit_log`, and the new `admin_rc_sync` (see §4).
  - `INSERT`/`UPDATE` on `plans`, `admin_grants`, `admin_rc_sync`, and `INSERT` on
    `admin_audit_log`.
  - `UPDATE` on `billing_events.processed`, for re-processing a webhook.
  - Nothing at all on `family_members`, `activities`, `coin_ledger`, `rewards`, `users` and the
    other content tables.
- **The role is created by `init-db.js`**, not by a `.sql` file, because it needs a password from
  the environment (`ADMIN_DB_PASSWORD`). The step is idempotent: create the role if it is
  missing, set its password, then apply the grants on every run. Production runs `db:init` on
  every start, so the grants can never drift.
- **Test:** an integration test connects as `carecoins_admin` and checks that a `SELECT` on
  `family_members`, `activities` and `coin_ledger` fails with a permission error. It runs in
  the existing E2E setup (`docs/automatic-testing-E2E.md`).

`requireAdmin` reads `users.platform_role`, which the admin role cannot read. Two options:
`admin-api` checks it through a third view, `admin_operators` (`id`, `firebase_uid`, filtered
to admins); or it keeps a small, separate connection as the main role for this one query.
**Recommended: the view**, so the whole process runs as one restricted role.

### 2.4 Secrets

A new `backend/admin.env`, gitignored and on the server only. It is used by `admin-api` and
`cloudflared`, never by `backend`:

| Variable | For |
|---|---|
| `ADMIN_DATABASE_URL` | `carecoins_admin` connection |
| `ADMIN_DB_PASSWORD` | read by `db-init` to set the role's password (also passed to `db-init`) |
| `RC_SECRET_API_KEY`, `RC_PROJECT_ID` | RevenueCat REST API v2 (secret key, `sk_…`) |
| `RC_ENTITLEMENT_ID` | the `MyCareCoins Pro` entitlement's id |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (.p8 contents) | App Store Connect API (catalogue, prices), signed JWT. A **team key** from Users and Access → Integrations → App Store Connect API |
| `IAP_KEY_ID`, `IAP_PRIVATE_KEY` (.p8 contents), `APP_BUNDLE_ID` | App Store Server API (transaction lookup). A **different key**: Users and Access → Integrations → In-App Purchase; creating it needs the Account Holder or Admin role. The issuer id is the same |
| `ASC_APP_ID` / bundle id | which app to read |
| `CF_ACCESS_TEAM_DOMAIN`, `CF_ACCESS_AUD` | Access token check |
| `CLOUDFLARE_TUNNEL_TOKEN` | `cloudflared` |
| `GOOGLE_APPLICATION_CREDENTIALS` | Firebase Admin, for checking ID tokens (same mounted file) |

The API keys get the narrowest rights the stores and RevenueCat allow:
- The App Store Connect key gets the **Customer Support** or **Developer** role. It must not be
  **Admin**, and it starts read-only (§3.4).
- The RevenueCat v2 key gets read on customers, subscriptions, products, offerings and metrics,
  and write on customer entitlements only.

---

## 3. What the console does

Every screen reads only registry and billing data. The console has no screen for members, tasks,
coins or rewards, the same as today.

### 3.1 Families (moved from the app, unchanged in substance)
- Search, filter by heartbeat bucket and plan, page through results.
- Family detail: registry card; billing card (plan, status, store, renewal, billing owner as
  a user id); free-plan grants; billing-event history; "notify inactive" with confirmation.

### 3.2 Subscriptions and RevenueCat
- **Per family:** the RevenueCat customer behind the subscription (linked by billing owner, and
  by the synthetic family customer for free plans, §4), with its live state from RevenueCat
  next to ours. If they disagree, for example a missed webhook, the console flags it.
- **Webhook health:** events with no family attribute, events that failed, the time since the
  last webhook arrived, and a **Re-process** action that runs one stored event through
  `billingService` again. It is idempotent, as before.
- **Overview:** RevenueCat's metrics overview: MRR, active subscriptions, active trials, new
  customers, revenue. Our own figures sit next to it: families per plan, per store, per status,
  and active free plans.

### 3.3 Plan catalogue
- Today's CRUD on `plans` (name, price display, period, limits, features, default, active).
- **Product mapping:** each plan shows which RevenueCat entitlement and products feed it, read
  from RevenueCat (`MyCareCoins Pro` → `pro`, products `monthly` / `yearly` / `lifetime`), with a
  warning if a product in RevenueCat maps to no plan.
- **Offerings:** list RevenueCat offerings and packages and show which one is current. Switching
  the current offering is a v2 write, and it changes what every paywall shows. It sits behind a
  confirmation and the recent-sign-in check. **Phase 4, optional** (§7).

### 3.4 App Store
- **Read:** the app's subscription group, products, prices per territory and review state
  (App Store Connect API).
- **Look up a transaction:** paste an original transaction id from a support email and see its
  status and history (App Store Server API). This is the only way to answer "I paid but I'm not
  Pro" without App Store Connect.
- **Links out** to App Store Connect, Play Console and the RevenueCat customer page, for
  refunds, price changes and anything else.
- Read-only at first. Price and product edits stay in App Store Connect, where Apple's review
  and agreements apply.

### 3.5 Audit
- A read-only list of `admin_audit_log`: who did what, when, and the result. Every mutating
  console call writes a row in the same transaction, as today. RevenueCat and App Store calls
  are logged with their outcome.

---

## 4. Free plans mirrored into RevenueCat

**The problem.** Our subscriptions are per family, while RevenueCat customers are per person:
`appUserID` is the backend user id. A free plan is an `admin_grants` row on a family. For
RevenueCat to count it, it has to become a **granted (promotional) entitlement on some
customer**.

**Design: one synthetic RevenueCat customer per family.**

- The customer id is `family_<familyId>`, created on first grant. Grants never go on a real
  person's customer. That person might also buy, leave the family, or belong to two families,
  and RevenueCat would then mix the free plan into their own history.
- On grant, `admin-api`:
  1. writes `admin_grants` + `admin_audit_log` in one transaction, as today;
  2. sets the customer's `family_id` attribute and grants entitlement `RC_ENTITLEMENT_ID` with
     `expires_at` = grant expiry. The v2 grant **requires** `expires_at`, so a grant with no
     expiry is sent as a far-future date (100 years). RevenueCat ignores a second grant for the
     same entitlement that expires within two hours of an existing one, so a re-sync is safe;
  3. records the result in `admin_rc_sync`.
- On revoke, it revokes the granted entitlement on that customer.
- **Our database decides what the family gets; RevenueCat mirrors it for statistics.** A
  RevenueCat failure never blocks a grant: the grant takes effect in our database, and the sync
  row says `pending` or `failed`. A retry loop inside `admin-api` (every 5 minutes, with backoff)
  and a **Retry** button resolve it. The console shows unsynced grants on the overview.
- **Webhook loop guard.** RevenueCat may send webhook events for granted entitlements (store
  `PROMOTIONAL`). `billingService` must **not** turn those into a `family_plans` store
  subscription: that would create a second, competing source of truth. They are logged in
  `billing_events` and marked processed as `promotional_mirror`, and nothing else happens.
  `billing.test.js` gets a case for this.
- **The app stays the same.** Families still read their plan from `/api/families/:id/entitlements`,
  which already merges `family_plans` and `admin_grants`. Nobody's device logs in as
  `family_<id>`, so the RevenueCat SDK cache on phones never sees the grant.

**New table:**

```sql
CREATE TABLE IF NOT EXISTS admin_rc_sync (
  grant_id      BIGINT PRIMARY KEY REFERENCES admin_grants(id) ON DELETE CASCADE,
  rc_customer_id TEXT NOT NULL,             -- 'family_<id>'
  action        TEXT NOT NULL CHECK (action IN ('grant','revoke')),
  status        TEXT NOT NULL CHECK (status IN ('pending','synced','failed')),
  attempts      INTEGER NOT NULL DEFAULT 0,
  last_error    TEXT,
  synced_at     TIMESTAMPTZ,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Existing families are test units (owner, 2026-10-15).** Every family in the database today is
test data, so nothing existing is pushed to RevenueCat: no backfill, no `family_<id>` customers
for them. Mirroring starts with grants made after Phase 3 ships. Nothing in this plan migrates or
cleans up those test families.

**Phase 0 findings (2026-10-15, from RevenueCat's current docs and forum):**

1. **The API exists.** REST API v2 has `POST /projects/{id}/customers` (create, with
   attributes), `…/customers/{id}/actions/grant_entitlement` (`entitlement_id`, `expires_at` in
   ms, required) and `…/actions/revoke_granted_entitlement`. No v1 calls are needed.
2. **RevenueCat's charts most likely do *not* count granted entitlements.**
   - RevenueCat staff said so explicitly: promotional grants don't renew and don't touch store
     billing, so they are left out of every chart, and the Customer List is the place to find
     them. That statement dates from 2022.
   - The current docs define Active Subscriptions as *paid* subscriptions.
   - Charts also show **production data only**, so the sandbox (Test Store) project cannot
     confirm or refute this. There is no production RevenueCat data yet: the project is still
     Test Store only (`docs/RevenueCatSetup.md`).
3. **Webhooks for grants are unreliable.** The event-types table marks most events as not sent
   for promotional grants. A staff reply says a grant sends `NON_RENEWING_PURCHASE` with store
   `PROMOTIONAL`, and a user reported never receiving it. The loop guard above stays either
   way. A sandbox grant will show what actually arrives.

**Decision 4, confirmed by the owner (2026-10-15): keep the mirror.** mirroring makes free-plan families
visible in RevenueCat's **Customer List, customer pages and data exports**, but most likely
**not in its charts or overview numbers**. Free plans would then be counted on the console's own
overview, which shows paid (from RevenueCat) and free (from our database) side by side. A
one-time check once production data exists (one grant on a `family_test` customer in the
production project, then revoked) settles item 2 for good.

---

## 5. Taking the console out of the subscriber app

Done last (Phase 5), once the new console is live and has been used.

| Remove | Where |
|---|---|
| `admin_screen.dart`, `AdminFamilyDetailScreen` | `fluterFront/lib/screens/` |
| The "Admin console" row | `profile_screen.dart` (~line 764) |
| `isPlatformAdmin` | `state/app_state.dart` |
| The 58 `admin*` keys | all four ARB files, then `flutter gen-l10n` |
| Admin widget tests | `fluterFront/test/` (they move, rewritten, to `adminFront/test/`) |
| `platform_role` in `/api/me` | `RETURNING` clauses in `backend/src/db/users.js` |
| `/api/admin` mount and `adminLimiter` | `backend/src/app.js` (the router moves to `src/admin/`) |

**Guard tests so it stays out:**
- Flutter: a test reads every file under `fluterFront/lib` and fails on `AdminScreen`,
  `platform_role`, `isPlatformAdmin` or `/api/admin`.
- Backend: a test calls the public `app` and expects **404** for `/api/admin/families`. It
  also checks that `/api/me` has no `platform_role`.
- Backend: `src/app.js` must not import anything under `src/admin/`. A simple file scan in a test
  enforces it.

**Release order matters:** ship the app build without the console *before* or *together with*
the backend change. An older app with the console still installed just gets a 404 if the
operator opens it, which is harmless, because only the operator ever sees that entry.

`docs/deployment-and-delivery.md`'s probe changes: `/api/admin/families` on
`mycarecoins.app` must now answer **404**, and the console's health is probed on
`admin.mycarecoins.app` with an Access service token.

---

## 6. Deployment changes

`docker-compose.yml` gains three services. The existing ones are unchanged, apart from `db-init`
getting `ADMIN_DB_PASSWORD`.

```yaml
  admin-api:
    build: ./backend
    command: node src/admin/server.js
    env_file: [./backend/admin.env]
    environment:
      PORT: 3001
      NODE_ENV: production
      GOOGLE_APPLICATION_CREDENTIALS: /run/secrets/firebase-credentials.json
    volumes:
      - ./firebase-credentials.json:/run/secrets/firebase-credentials.json:ro
    depends_on: { db-init: { condition: service_completed_successfully } }
    # no ports: reached only from admin-web on the internal network

  admin-web:
    build: { context: ./adminFront }
    depends_on: [admin-api]
    # no ports: reached only through cloudflared

  cloudflared:
    image: cloudflare/cloudflared:<pinned version>
    command: tunnel --no-autoupdate run
    env_file: [./backend/admin.env]   # CLOUDFLARE_TUNNEL_TOKEN
    depends_on: [admin-web]
```

- **Separate networks:** `admin-web` and `cloudflared` sit on an `admin` network, and
  `frontend` is not on it. `admin-api` sits on both the `admin` network and the internal
  database network.
- **`adminFront/Dockerfile`:** a multi-stage build (Flutter SDK image → `flutter build web` →
  nginx), the same pattern as `fluterFront/`. Its `nginx.conf` proxies `/admin-api` to
  `admin-api:3001`, and sends `X-Robots-Tag: noindex` and a strict CSP.
- **`admin-api` CORS:** same origin only, because nginx proxies it. CORS stays closed, plus a
  stricter rate limit than the public API.
- **`scripts/deploy.sh`:**
  - Builds the new services; `docker compose up --build -d` already covers that.
  - Gains a pre-flight check that `backend/admin.env` exists on the server, and a post-deploy
    probe of the console.
  - Keeps `--dry-run` first.
- **Cloudflare, once, by hand:**
  - Create the tunnel and its public hostname `admin.mycarecoins.app` → `http://admin-web:80`.
  - Create the Access application with an allow policy for the owner's email.
  - Copy the audience tag into `CF_ACCESS_AUD`.
  - Add `admin.mycarecoins.app` to the Firebase authorised domains.
- **Server sizing:** two small Node and nginx containers plus `cloudflared`. A Flutter web build
  in Docker needs about 2 GB of RAM at build time; if the server is tight, build `adminFront`
  locally and ship the `build/web` output instead (decide in Phase 1).

---

## 7. Phases

Each phase ends with `npm test` and `flutter analyze && flutter test` clean (in `adminFront/`
too, once it exists), and with this plan's **As built** log updated.

### Phase 0 — Spikes and console setup · S (1 day)

Research is done (findings in §4). What is left needs the owner's accounts.

**Owner, in the consoles (about 1 hour):**
- [ ] **RevenueCat** (sandbox project) → Project settings → API keys → new **secret v2 key**.
      Permissions: Customer information read & write, Project configuration read, Charts & metrics
      read. Note the project id (`proj…`) and the entitlement's id for `MyCareCoins Pro`.
- [ ] **App Store Connect** → Users and Access → Integrations:
  - [ ] App Store Connect API → Team key, role **Customer Support** (read-only enough for
        products, prices and subscription status; try **Developer** if a read fails). Note
        the key id and issuer id.
  - [ ] In-App Purchase → generate a key (needs Account Holder or Admin). Note its key id.
  - [ ] Keep both `.p8` files out of the repo and out of chat; they download only once.
- [ ] **Cloudflare** → Zero Trust:
  - [ ] Create the team (free plan) if none exists.
  - [ ] Networks → Tunnels → create a tunnel `carecoins-admin` (cloudflared); keep its token.
  - [ ] Access → Applications → self-hosted app for `admin.mycarecoins.app`, policy: allow your
        email; note the team domain and the **AUD tag**.
- [ ] **Firebase** → Authentication → Settings → Authorized domains → add `admin.mycarecoins.app`.

**Lead, once the RevenueCat key is in a local env file (not in the repo):**
- [ ] A throwaway script against the **sandbox** project: create `family_test`, set its
      `family_id` attribute, grant `MyCareCoins Pro` for 1 day, read the customer back, revoke.
      Record the responses and which webhook events reach the backend's billing log.
- [ ] Call `GET /metrics/overview` and record the metric ids it returns, for the console's
      overview.
- [ ] Write the results into §4 and the As built log.

**Exit:** the owner confirms decision 4 in its revised form (mirror for the Customer List; count
free plans on the console), or drops the mirror. Phase 1 does not depend on this decision, so
it can start in parallel.

### Phase 1 — `admin-api` skeleton and the database role · M (2–3 days)
- `backend/src/admin/{server,app}.js`: the Access token check → Firebase auth → `requireAdmin`
  (via `admin_operators`) → rate limit → router. Move the existing admin router and
  `adminService` usage here; at this point the public `app.js` **still** mounts `/api/admin`,
  so nothing breaks.
- Migration `migrate-admin-role.sql`: the views (`admin_family_registry`, `admin_billing_owner`,
  `admin_operators`) and `admin_rc_sync`. Mirrored in `schema.sql`, chained in `init-db.js`,
  plus the idempotent role and grants step.
- `adminService` reads through the views instead of the base tables.
- Compose: the `admin-api` service, the `admin.env` template (`backend/admin.env.example`,
  committed with no values), and `db-init` getting `ADMIN_DB_PASSWORD`.
- **Tests:** existing admin tests pass against the new app; Access-token check (valid, missing,
  wrong audience); the permission-denied E2E check (§2.3); `db:init` run twice.

### Phase 2 — `adminFront` with today's features · M (3–4 days)
- New Flutter web project: Firebase sign-in, the API client with `/admin-api`, desktop layout.
  Theme tokens copied from `fluterFront/lib/theme/app_theme.dart`. English strings live in
  one `strings.dart` (no ARB files: one operator, one language; noted in `CLAUDE.md`).
- Port Families, Family detail, Plans and grants from `admin_screen.dart`. Use the room a desktop
  gives: tables, not cards.
- `adminFront/Dockerfile` + nginx; compose `admin-web` + `cloudflared`; Cloudflare hostname
  pointed at it.
- **Exit:** the owner uses the new console in production for everything the in-app console
  does today. The in-app console is still there as a fallback.

### Phase 3 — RevenueCat · M (3–4 days)
- `src/admin/revenuecat.js`: a small v2 client (customers, subscriptions, entitlements grant and
  revoke, products, offerings, metrics overview), with timeouts and errors mapped to the server
  error codes from Phase 6 of the UX work.
- Free-plan mirroring (§4): sync on grant and revoke, the retry loop, and the Retry button
  (no backfill: existing families are test data).
- `billingService`: the `PROMOTIONAL` loop guard + test.
- Console: RevenueCat state per family and mismatch flags, webhook health and Re-process, the
  overview with metrics, product-to-plan mapping.
- **Tests:** RevenueCat client against recorded responses (no network in `npm test`); a grant
  that fails at RevenueCat still takes effect in our database and leaves `pending`; the retry
  loop moves it to `synced`; a revoke removes it; `PROMOTIONAL` webhooks never write
  `family_plans`.

### Phase 4 — App Store · S–M (2–3 days)
- `src/admin/appstore.js`: signed-JWT clients for the App Store Connect API (team key:
  subscription group, products, prices) and the App Store Server API (In-App Purchase key:
  transaction lookup and history). These are two different keys; tokens live up to 60 minutes
  and are reused for that long.
- Console: App Store page, transaction lookup, links out to the store consoles.
- Optional, behind the recent-sign-in check: switching RevenueCat's current offering.
- **Tests:** JWT signing (claims, expiry), recorded responses, no secret ever in a response or
  log line.

### Phase 5 — Take the console out of the app · S (1–2 days)
- Everything in §5: remove the code, the keys and `platform_role`, unmount `/api/admin`, add the
  guard tests.
- App release (iOS + Android + web) and backend deploy, in the order from §5.
- Update `docs/backend.md`, `docs/flutter-frontend.md`, `docs/deployment-and-delivery.md` (probe,
  compose, Cloudflare steps, `admin.env`), `docs/database-schema.md` (views, role,
  `admin_rc_sync`), `docs/agent-setup.md` if tooling changed, `CLAUDE.md` (layout table,
  the English-only console exception, the role rule), and mark
  `admin-family-management-plan.md` Phase 5 as superseded.

**Total:** about 12–17 working days, plus Apple and Cloudflare setup time.

---

## 8. Risks and how the plan handles them

| Risk | Handling |
|---|---|
| RevenueCat charts do not count promotional grants the way we want | Phase 0 checks it before any build; the console's own overview is the fallback |
| Mirroring creates a second source of truth | Our DB is authoritative; RevenueCat is a mirror; `PROMOTIONAL` webhooks never write `family_plans` |
| Losing access to the console (Access misconfigured, tunnel down) | `promote-admin.js` and the retention CLI still work over SSH; during Phases 2–4 the in-app console is still there as a fallback |
| Secret keys leak | Only in `admin.env` on the server; narrowest key roles; tests check that responses and logs never contain them |
| A Flutter web build is heavy for the server | Decide in Phase 1: build on the server or ship `build/web` |
| The database role's grants drift from new tables | Grants are applied on every `db:init`; the permission-denied test lists the content tables, so add new content tables to it |
| Recent sign-in check annoys the operator | 30 minutes, only for mutations; easy to tune |

---

## 9. Open items (to settle during the phases)

1. Recent sign-in window for mutations (proposed 30 min).
2. Whether the console should also show Google Play data (Play Developer API). This plan
   leaves Play to RevenueCat's view plus a link out to Play Console.
3. Whether the operator should be able to change a family's RevenueCat customer attributes
   (for example to fix an unattributed purchase by hand), or only re-process the webhook.
   Proposed: re-process only, plus a documented manual fix in RevenueCat.
4. The Phase 0 findings on RevenueCat charts and webhook events (§4).

---

## As built

*(Filled in per phase.)*
