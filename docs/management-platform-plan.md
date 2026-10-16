# Management Platform (Operator Console) — Plan

> **Status: Phase 2 code done, not deployed** (2026-10-15). Phase 0 research done; console setup (keys,
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

- **Views owned by the main role (`security_barrier`).** Postgres runs a view with its owner's rights,
  so the views can count rows the admin role itself cannot read:
  - `admin_family_registry`: family id, name, created_at, last_active_at, plan_code, subscription_status,
    member_count, pending_member_count, actor_count. These are the columns `adminService` already returns.
  - `admin_operators`: id, firebase_uid for platform admins (`platform_role = 'admin' AND is_deleted = false`).
    `requireOperator` (`src/admin/operator.js`) checks callers here without reading `users` directly or upserting them.
  - *(Deviation from early draft)*: No `admin_billing_owner` view is needed because `family_plans` is granted whole.
- **Queue for notices (`admin_family_notices`):**
  The admin role cannot see who is in a family, so it cannot push directly. `requestInactivityNotice`
  inserts a row into `admin_family_notices` (`id`, `family_id`, `kind`, `requested_by`, `created_at`, `sent_at`),
  and the public backend's notice outbox (`src/services/noticeOutbox.js`) periodically claims pending rows
  (`FOR UPDATE SKIP LOCKED`) and pushes to the family's caregivers.
- **Grants for `carecoins_admin` (`scripts/admin-role.js`):**
  - `SELECT` on `admin_family_registry`, `admin_operators`, `plans`, `family_plans`, `admin_grants`,
    `admin_audit_log`, `admin_rc_sync`, `admin_family_notices`.
  - Column-restricted `SELECT (id, provider, event_id, event_type, family_id, processed, created_at)`
    on `billing_events` (raw `payload` is omitted to protect customer attributes; re-processing in Phase 3
    will need a dedicated route).
  - `INSERT`, `UPDATE` on `plans` and `admin_rc_sync`.
  - `INSERT`, `UPDATE (revoked_at)` on `admin_grants`.
  - `INSERT` on `admin_audit_log` and `admin_family_notices`.
  - `USAGE` on sequences `admin_grants_id_seq`, `admin_audit_log_id_seq`, `admin_family_notices_id_seq`.
  - Nothing at all on `family_members`, `activities`, `coin_ledger`, `rewards`, `users` or any other of the 18 content tables in `FORBIDDEN_TABLES`.
- **The role is created/maintained by `scripts/admin-role.js`**, chained in `init-db.js`, from `ADMIN_DB_PASSWORD`.
  The step is idempotent: creates the role if missing, sets password, revokes all existing schema grants,
  then reapplies the allowlist. When `ADMIN_DB_PASSWORD` is absent (local dev without role setup), `init-db.js` skips role creation.
  In `admin-api`, the password is supplied to `pg` via `PGPASSWORD` (`src/admin/env.js`) from `ADMIN_DB_PASSWORD`
  (`backend/admin-db.env`), keeping the connection URL password-free.
- **Test:** `scripts/check-admin-role.js` verifies against a real Postgres container that every content table is refused,
  payload is refused, grants work, and every table in the schema is classified.

### 2.4 Secrets

A new `backend/admin.env`, gitignored and on the server only. It is used by `admin-api`,
never by `backend` or `cloudflared`:

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
| `FIREBASE_PROJECT_ID` | Firebase project used to check operators' ID tokens |
| `GOOGLE_APPLICATION_CREDENTIALS` | Firebase Admin, for checking ID tokens (same mounted file) |

A separate `backend/tunnel.env` (template `backend/tunnel.env.example`) holds `TUNNEL_TOKEN`
for `cloudflared`. `admin-api` never gets the tunnel token, and `cloudflared` gets no database
or store keys.

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
getting `ADMIN_DB_PASSWORD` from `./backend/admin-db.env` (using the long `env_file` syntax with
`required: false` so deploys succeed even without the file).

```yaml
  admin-api:
    build: ./backend
    command: node src/admin/server.js
    profiles: [admin]
    environment:
      DATABASE_URL: postgres://carecoins_admin@postgres:5432/carecoins
      PORT: 3001
      NODE_ENV: production
      GOOGLE_APPLICATION_CREDENTIALS: /run/secrets/firebase-credentials.json
    env_file:
      - ./backend/admin.env
      - ./backend/admin-db.env
    depends_on:
      db-init:
        condition: service_completed_successfully
      postgres:
        condition: service_healthy
    volumes:
      - ./firebase-credentials.json:/run/secrets/firebase-credentials.json:ro
    networks:
      - default
      - admin

  admin-web:
    build: ./adminFront
    profiles: [admin]
    depends_on:
      - admin-api
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:80/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - admin

  cloudflared:
    image: cloudflare/cloudflared:2025.2.1
    command: tunnel --no-autoupdate run
    profiles: [admin]
    env_file:
      - ./backend/tunnel.env
    depends_on:
      - admin-web
    networks:
      - admin

networks:
  admin:
```

- **Separate networks:** `admin-web` and `cloudflared` sit on an `admin` network only, and
  `frontend` is on `default` only. `admin-api` sits on both `default` (to reach postgres)
  and `admin` (to receive requests from `admin-web`). `frontend` cannot resolve `admin-web`.
- **`adminFront/Dockerfile`:** a multi-stage build (pinned Flutter SDK `ghcr.io/cirruslabs/flutter:3.44.0` →
  `flutter build web --release --dart-define=API_BASE= --no-web-resources-cdn` → `nginx:1.27-alpine`).
  CanvasKit and fonts are bundled inside the container to avoid external CDN requests.
- **`nginx.conf`:** proxies `/admin-api/` to `admin-api:3001` (forwarding `Authorization` and
  `Cf-Access-Jwt-Assertion`), provides `/health` returning 200 for compose health checks, applies
  cache-busting rules to `index.html` and service workers, and injects `X-Robots-Tag: noindex, nofollow`,
  `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, and a strict CSP.
- **`admin-api` CORS:** same origin only, because nginx proxies it. CORS stays closed, plus a
  stricter rate limit than the public API.
- **`scripts/deploy.sh`:**
  - Builds the new services; `docker compose up --build -d` already covers that.
  - Gains a pre-flight check that `backend/admin.env` and `backend/tunnel.env` exist on the server,
    and a post-deploy probe of the console.
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
  transaction lookup and history). These are two different keys: Connect API tokens are capped
  at 20 minutes (issue for 19 min, reuse until 18 min); Server API tokens live up to 60 minutes
  (issue for 55 min, reuse until 54 min).
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

### Phase 1 — `admin-api` skeleton and the database role (2026-10-15)

The operator console's backend skeleton and the Postgres security boundary are complete in code.

**Files built / touched:**
- `backend/scripts/migrate-admin-console.sql`: creates views `admin_family_registry` and `admin_operators` (both `security_barrier`), and tables `admin_family_notices` (queue for inactivity notices) and `admin_rc_sync` (free-plan RevenueCat sync tracking).
- `backend/src/db/schema.sql`: mirrors the migration at the end.
- `backend/scripts/admin-role.js`: creates/maintains the restricted `carecoins_admin` Postgres role from `ADMIN_DB_PASSWORD`; revokes all schema grants on each run then reapplies explicit allowlist. Defines `FORBIDDEN_TABLES` (18 content tables).
- `backend/scripts/init-db.js`: chains `migrate-admin-console.sql` and calls `applyAdminRole(pool)`.
- `backend/scripts/check-admin-role.js`: real-Postgres verification against Postgres 16: verifies role refusal on all 18 content tables, refusal of `billing_events.payload`, refusal of schema mutations, verifies that views and console operations succeed, and confirms every base table is classified.
- `backend/src/admin/env.js`: loads `.env` and wires `ADMIN_DB_PASSWORD` to `PGPASSWORD` so the database URL stays free of embedded passwords.
- `backend/src/admin/access.js`: verifies Cloudflare Access JWTs (`cf-access-jwt-assertion`) using `jose` against `CF_ACCESS_TEAM_DOMAIN` and `CF_ACCESS_AUD`. Fails startup in production if unset.
- `backend/src/admin/operator.js`: `requireOperator` verifies admin status against the `admin_operators` view (no user table reads or upserts); `requireRecentSignIn` enforces `auth_time` within 30 minutes for mutating methods (reads pass).
- `backend/src/admin/app.js`: Express app mounting `/health` and `/admin-api` with middleware chain: Access check → Firebase Auth → per-operator rate limit (300/15m) → `requireOperator` → `requireRecentSignIn` → `adminRouter`.
- `backend/src/admin/server.js`: entrypoint on port 3001; verifies connection role is `carecoins_admin` on boot (refuses startup in production otherwise).
- `backend/src/services/adminService.js`: refactored to read families through `admin_family_registry`; `requestInactivityNotice` queues into `admin_family_notices`.
- `backend/src/routes/admin.js`: updated to queue inactivity notices rather than pushing directly; mounted under both `/api/admin` (temporary) and `/admin-api`.
- `backend/src/services/noticeOutbox.js` + `backend/src/server.js`: background worker in public backend polling `admin_family_notices` every 60s, claiming rows with `FOR UPDATE SKIP LOCKED`, and delivering caregiver pushes.
- `docker-compose.yml`: adds `admin-api` behind `profiles: [admin]`, wires `admin-db.env` to `db-init` with `required: false`.
- `backend/tests/adminConsole.test.js`: 20 tests covering Access JWT verification, operator authorization, recent sign-in enforcement, separation from public app (`src/app.js` never imports `src/admin/`), grant rules, and notice outbox.
- `backend/tests/adminRegistry.test.js`: updated for notice queue and view changes.
- `docs/error-codes.md`: registered `accessInvalid`, `accessMissing`, `adminReauthRequired`.
- `fluterFront/test/server_errors_p6_6_test.dart`: exempts operator console error codes from app localization.
- `backend/admin.env.example`, `backend/admin-db.env.example`, `.gitignore`, `backend/.dockerignore`: env templates and ignore rules.
- `backend/package.json`: added `jose` ^6.

**Decisions & deviations recorded:**
- *No `admin_billing_owner` view*: `family_plans` is granted whole to `carecoins_admin`, so the view was redundant.
- *Notice outbox queue (`admin_family_notices`)*: because `carecoins_admin` cannot view family members or users, it queues inactive notices. The public backend claims and sends them.
- *Column grant on `billing_events`*: granted without `payload` column to protect member attributes in webhooks. Re-processing webhooks (Phase 3) is noted as an open item requiring an alternate route.
- *`PGPASSWORD` for `carecoins_admin`*: avoids storing DB passwords in connection URLs.
- *Compose profile `admin`*: ensures regular `docker compose up` / `deploy.sh` does not run `admin-api` until Phase 2 is ready.

**Test & verification results:**
- Backend unit suite: 253 tests passing (`npm test`).
- Flutter suite: 315 tests passing, `flutter analyze` clean (`flutter test`).
- Real-Postgres verification against `postgres:16` container (`check-admin-role.js`): all 31 checks passed; `db:init` verified idempotent twice.
- Boot check: `GET /health` returned HTTP 200, `GET /admin-api/status` returned HTTP 401 `authMissingToken`.
- Compose config verified valid both with and without `--profile admin`.

### Phase 2 — `adminFront` Flutter web console, container, and tunnel (2026-10-15)

The operator console's frontend and deployment packaging are complete in code. The console is a standalone Flutter web app (`adminFront/`) packaged into an nginx container (`admin-web`), orchestrated with `admin-api` and `cloudflared` under the `admin` compose profile, and isolated onto an internal `admin` Docker network.

**Files built / touched:**
- `adminFront/`: Standalone Flutter web project (own `pubspec.yaml`, no imports from `fluterFront`).
  - `lib/main.dart`, `lib/app_state.dart`, `lib/api.dart`, `lib/auth.dart`: Console bootstrapping, state management, HTTP client targeting same-origin `/admin-api/`, Firebase Auth service, and recent sign-in re-auth dialog.
  - `lib/strings.dart`: English-only user-facing string catalogue and error code mappings (`FirebaseAuthException` and backend codes).
  - `lib/theme.dart`: Operator desktop theme tokens copied from `fluterFront` design system.
  - `lib/screens/sign_in_screen.dart`: Google and Email/Password sign-in with mapped error feedback.
  - `lib/screens/families_screen.dart`: Desktop table of families (ID, Name, Heartbeat, Plan, Subscription, Members, Created, Last Active, Actions), debounced search, status filter, and pagination with singular/plural formatting. Horizontal scrollbar on viewports narrower than 1440 px.
  - `lib/screens/family_detail_screen.dart`: Registry overview, subscription details, plan grants with status badges (Active, Expired, Revoked) and grant/revoke flows, recent billing events, and inactivity notification dispatch.
  - `lib/screens/plans_screen.dart`: Plan catalogue list and dialogs for creating and editing plans.
  - `web/manifest.json`: Updated `name` and `short_name` to "CareCoins Operator".
  - `test/`: 22 Flutter widget and unit tests (`auth_status_test.dart`, `error_mapping_test.dart`, `families_test.dart`, `family_detail_test.dart`, `plans_test.dart`, `reauth_test.dart`, `guard_test.dart`, `fakes.dart`).
- `adminFront/Dockerfile`: Multi-stage Dockerfile pinning `ghcr.io/cirruslabs/flutter:3.44.0` for web compilation with `--no-web-resources-cdn` (bundling CanvasKit and fonts locally) and `nginx:1.27-alpine` runtime, copying `security-headers.conf` into `/etc/nginx/snippets/`.
- `adminFront/.dockerignore`: Excludes `build/`, `.dart_tool/`, `test/`, `.git/`, `.idea/`, `*.log`.
- `adminFront/security-headers.conf`: Single snippet defining the 5 security headers (CSP, `X-Robots-Tag: noindex, nofollow`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`).
- `adminFront/nginx.conf`: Nginx server block including `security-headers.conf` at server and location levels, proxying `/admin-api/` to `http://admin-api:3001` (preserving `Authorization` and `Cf-Access-Jwt-Assertion`) using Docker internal resolver `127.0.0.11` only (no public DNS), container healthcheck `/health` returning 200, cache-busting headers for index/bootstrap files, and SPA fallback.
- `backend/tunnel.env.example`: Dedicated template for the Cloudflare Tunnel token (`TUNNEL_TOKEN`).
- `backend/admin.env.example`: Removed `CLOUDFLARE_TUNNEL_TOKEN` so token lives exclusively in `tunnel.env`.
- `backend/.dockerignore` & `.gitignore`: Added `tunnel.env` ignore rules alongside `admin.env`.
- `docker-compose.yml`: Added `admin-web` and `cloudflared` services (pinned to `cloudflare/cloudflared:2026.10.1`) under profile `admin`, added `admin` bridge network, attached `admin-api` to `default` and `admin`, and isolated `admin-web` and `cloudflared` to `admin` only.
- `CLAUDE.md`: Added `adminFront/` layout entry, test command, and strings exception rule.

**Content Security Policy (CSP) specification and host rationale:**
The console enforces a strict CSP on every response:
`default-src 'self'; script-src 'self' 'wasm-unsafe-eval' https://apis.google.com; worker-src 'self' blob:; connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://www.googleapis.com; frame-src https://tfg-carecoins.firebaseapp.com https://accounts.google.com; img-src 'self' data: https://lh3.googleusercontent.com; style-src 'self' 'unsafe-inline'; font-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none';`

- `default-src 'self'`: Restricts all unspecified resource loads to same-origin.
- `script-src 'self' 'wasm-unsafe-eval' https://apis.google.com`: `'self'` and `'wasm-unsafe-eval'` are required for Flutter Web and CanvasKit WebAssembly execution; `https://apis.google.com` is required by the Google Sign-In SDK for Google auth popups.
- `worker-src 'self' blob:`: Flutter Web CanvasKit spawns web workers from `blob:` URLs for rendering thread pools.
- `connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://www.googleapis.com`: Firebase Auth REST endpoints for credential verification, token refresh, and Google OAuth; `'self'` for proxied `/admin-api/` calls.
- `frame-src https://tfg-carecoins.firebaseapp.com https://accounts.google.com`: Firebase Auth iframe handler (`tfg-carecoins.firebaseapp.com` from `DefaultFirebaseOptions.web.authDomain`) and Google account picker iframe.
- `img-src 'self' data: https://lh3.googleusercontent.com`: Operator avatar thumbnails from Google user accounts and inline data URLs.
- `style-src 'self' 'unsafe-inline'`: Flutter web layout and bootstrap styles.
- `font-src 'self' data:`: Roboto and MaterialIcons fonts bundled locally via `--no-web-resources-cdn`.
- `object-src 'none'`: Disallows plugins and Flash.
- `base-uri 'self'`: Prevents `<base>` tag hijacking.
- `frame-ancestors 'none'`: Prevents clickjacking by blocking embedding inside any iframe.

**Decisions & deviations recorded:**
- *Dedicated `tunnel.env`*: Isolated `TUNNEL_TOKEN` from `admin.env` so `cloudflared` receives only its tunnel token and no database credentials or store keys, and `admin-api` receives no tunnel secrets.
- *Bundled web resources (`--no-web-resources-cdn`)*: CanvasKit and web fonts are baked into the container image during build, eliminating external runtime dependencies on `gstatic.com` and keeping CSP strict.
- *Runtime upstream resolution in nginx with internal DNS only*: `nginx.conf` uses `resolver 127.0.0.11 valid=30s ipv6=off;` (no public DNS) and variable proxying for `admin-api:3001`. This allows `admin-web` to boot and serve static pages standalone even if `admin-api` is not yet running, returning 502 on API calls rather than crashing nginx on boot.
- *Unified security headers snippet*: Security headers are maintained in a single snippet (`security-headers.conf`) and included at server level and in each location block with distinct `add_header` caching directives.
- *Guard test enforcement*: `guard_test.dart` asserts no imports from `fluterFront` and no raw string literals outside `strings.dart`.

**Test & verification results:**
- `adminFront` test suite: 22 tests passing clean (`flutter test`).
- `adminFront` static analysis: zero issues found (`flutter analyze`).
- Web release build: succeeds cleanly (`flutter build web --release --dart-define=API_BASE=`).
- Docker build: `docker build -t cc-admin-web ./adminFront` built successfully; content size 36.2 MB.
- Standalone container proof (`cc-aw` on port 18080):
  - `GET /` returned HTTP 200 with all security headers (`X-Robots-Tag: noindex, nofollow`, CSP, frame options).
  - `GET /health` returned HTTP 200 `OK`.
  - `GET /families/1` returned HTTP 200 with SPA fallback and security headers.
  - `GET /admin-api/status` returned HTTP 502 (no upstream `admin-api`).
- Compose verification: `docker compose config -q` and `docker compose --profile admin config -q` both pass cleanly; default profile excludes all admin services.

### Phase 2 follow-up — MP2c: closing Phase 2 API gaps (2026-10-16)

Closed three of the API gaps found during Phase 2; the fourth was not a bug:

1. **`GET /families` counts**: `listFamilies` and `getFamilyRegistry` in `adminService.js` now share `toRegistryEntry`, selecting and returning `pendingMemberCount` and `actorCount` alongside baseline family registry fields. The frontend `families_screen.dart` restores the **Pending** and **Actors** columns; all 11 columns remain fully visible at 1440 px with horizontal scrolling supported below that.
2. **`GET /families/:id/billing` owner**: selects `billing_owner_user_id` from `family_plans` and returns `billingOwnerUserId` (number or `null`) under `subscription`. No join to `users` or user identities is performed, strictly preserving `carecoins_admin` role restrictions. The frontend billing card displays the **Billing owner** row as `User #<id>` or `—` when unassigned.
3. **Structured 429 rate limit responses**: `operatorLimiter` in `src/admin/app.js` configures a custom `handler` returning `{ error: 'Too many requests. Please try again later.', code: 'rateLimited' }`, matching standard backend error format. Catalogued `rateLimited` in `docs/error-codes.md` (Operator console API only).
4. **Plan field naming**: The snake_case keys inside plan `limits` (`max_members`, `max_actors`, `max_active_rewards`) are stored entitlement data read by existing services (`memberService.js` and `marketplace.js`); renaming them would require a data migration for no gain, so they are kept as-is.

**Test & verification results:**
- Backend unit suite: 255 tests passing (`npm test`), including rate limiter test returning 429 `{ code: 'rateLimited' }` and entitlement billing owner tests.
- `adminFront` test suite: 25 tests passing, `flutter analyze` clean (`flutter test`).

### Phase 2 follow-up — MP2d: `deploy.sh --admin` automation (2026-10-16)

Added the opt-in `--admin` flag to `scripts/deploy.sh` to package, sync secrets for, rebuild, and verify the operator console stack (`admin-api`, `admin-web`, `cloudflared`) on production deploys:
- **Secrets & preflight**: Appends `backend/admin.env`, `backend/admin-db.env`, and `backend/tunnel.env` to the secrets sync, validating that `TUNNEL_TOKEN`, `CF_ACCESS_AUD`, `CF_ACCESS_TEAM_DOMAIN`, and `ADMIN_DB_PASSWORD` are non-empty without logging values.
- **Compose profile**: Wires `COMPOSE="docker compose --profile admin"` into all lifecycle steps (up, ps, `down -v` on `--reset-db`, logs and the rollback hint). The backup `pg_dump` and the post-reset `psql` checks stay on plain `docker compose`: postgres is not in the profile, and on a first `--admin` deploy the console's env files reach the server only after the backup, so `--profile admin` would make compose refuse to run.
- **Tested by the lead** against fake `ssh`/`scp`/`curl` in a throwaway clone (never against the server): dry run, a good deploy (302 to Access), a console answering 200 (two failures in red), `cloudflared` not running (one failure), an empty `TUNNEL_TOKEN` (stops before any SSH write), and a plain deploy while the console runs (warning).
- **Console verification**: Asserts that `admin-api`, `admin-web`, and `cloudflared` are running, and probes `$DEPLOY_ADMIN_URL/` and `$DEPLOY_ADMIN_URL/admin-api/status` without redirects, requiring HTTP 302 to `*.cloudflareaccess.com` or HTTP 403, and flagging HTTP 200/401 as critical security alerts.
- **Un-flagged deploys**: Without `--admin`, checks whether console containers are currently running on the server and issues a warning to include `--admin`.

### Phase 3 — part 1 (MP3a): RevenueCat client, free-plan mirror, loop guard (2026-10-16)

Groundwork for Phase 3 free-plan mirroring into RevenueCat and billing loop protection:
1. **Loop guard**: In `backend/src/services/billingService.js`, webhooks with `event.store === 'PROMOTIONAL'` are acknowledged, marked `processed = true` in `billing_events`, return `{ data: { ignored: 'promotional_mirror' } }`, and never touch `family_plans` or `plans`. Verified for both `NON_RENEWING_PURCHASE` and `INITIAL_PURCHASE`.
2. **RevenueCat v2 Client**: In `backend/src/admin/revenuecat.js`, built `createRevenueCatClient({ apiKey, projectId, fetch, timeoutMs })` supporting `ensureCustomer`, `grantEntitlement`, `revokeGrantedEntitlement`, and `getCustomer`, with `RevenueCatError` distinguishing `unavailable` (timeouts, network, 429, 5xx) from `rejected` (other 4xx) errors, strictly preventing API key leakage in errors or logs (no `apiKey` or `projectId` getters). All endpoints use the official v2 reference (`https://www.revenuecat.com/docs/api-v2/customer`). Config parsed via `revenueCatConfigFromEnv(env)`. Mock fixtures established under `backend/tests/fixtures/revenuecat/*.json`.
3. **Mirror Sync**: In `backend/src/services/adminService.js`, `createGrant` queues a `grant` row into `admin_rc_sync` in the same transaction, while `revokeGrant` upserts an action `revoke` row. `syncPending` in `backend/src/admin/rcSync.js` claims due pending/failed rows with `FOR UPDATE SKIP LOCKED` using exponential backoff (`updated_at + min(2^attempts, 60) minutes`), defaulting lifetime grants to now + 100 years. In `backend/src/admin/server.js`, periodic sync runs every 5 minutes (and on boot) when configured; otherwise logs "RevenueCat mirror off". The mirror remains **off** until `RC_SECRET_API_KEY`, `RC_PROJECT_ID`, and `RC_ENTITLEMENT_ID` are configured in `backend/admin.env`.
4. **RevenueCat sync behaviors**:
   - *Array attributes*: Customer attributes payload uses an array format `[{ name: 'family_id', value: '...' }]` on create and attribute update.
   - *Revoke re-grant*: Revoking an entitlement removes all grants on that customer, so if the family still has another active grant, `rcSync` immediately re-grants with the latest remaining expiry (null → now + 100 years) in the same sync step.
   - *404 on revoke*: A revoke returning 404 (customer or granted entitlement never existed in RevenueCat) counts as `synced`.
   - *Expired grant bypass*: If a pending grant's expiry has already passed (`expires_at <= now`), it is marked `synced` without calling RevenueCat (nothing left to mirror).
5. **Retry & Console UI**: Added `POST /admin-api/families/:familyId/grants/:grantId/rc-sync` (restricted to admin console router only; does not exist on public `/api/admin`), protected by recent sign-in (`requireRecentSignIn`), auditing `grant.rc_retry`. When mirror is off, returns `{ status: 'pending', mirror: 'off' }`; when on, executes `syncPending` for that grant and returns updated status. Retrying a grant with no sync record returns 404 `notFound`, and unexpected sync errors return 500 `internal`. In `adminFront`, the family detail grants table displays the **RevenueCat** column (Synced / Pending / Failed with error tooltip / —) and a **Retry** button on Pending/Failed rows going through operator re-auth.
6. **Sandbox verification outstanding**: The lead's sandbox test with real RevenueCat keys must still replace mock fixtures with recorded responses and confirm whether `NON_RENEWING_PURCHASE` or other webhook events arrive for promotional grants.

### Phase 4 (MP4a) — App Store clients and console page (2026-10-16)

App Store Connect and App Store Server API clients and the operator console App Store screen are complete in code:
1. **Tokens & Security**:
   - `backend/src/admin/appstore.js`: Built signed-JWT token makers for both App Store Connect API (team key: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `aud: 'appstoreconnect-v1'`, capped at 20 minutes: issued for 19 min, reused up to 18 min) and App Store Server API (In-App Purchase key: `IAP_KEY_ID`, `ASC_ISSUER_ID`, `APP_BUNDLE_ID`, `IAP_PRIVATE_KEY`, `aud: 'appstoreconnect-v1'`, `bid`, capped at 60 minutes: issued for 55 min, reused up to 54 min).
   - Keys parsed as PEM from env (handling `\n` escapes). Sensitive keys and tokens are never logged or included in error messages (verified by tests).
   - "Off until configured": `appStoreConfigFromEnv(env)` returns `{ connect, server }` with missing parts as `null`. When keys are incomplete, endpoints return HTTP 503 `appStoreNotConfigured`.
2. **App Store Clients**:
   - **Connect API client**: `getApp(bundleId)`, `listSubscriptionGroups(appId)`, `listSubscriptions(groupId)`, `listSubscriptionPrices(subscriptionId)`, and `getCatalog(bundleId)` traversing groups, subscriptions, and territory price points.
   - **Server API client**: `getTransaction(id)` (`/inApps/v1/transactions/{id}`), `getSubscriptionStatuses(id)` (`/inApps/v1/subscriptions/{id}`), and `lookupTransaction(id)`. Signed JWS payloads (`signedTransactionInfo`, `signedRenewalInfo`) are decoded using `jose.decodeJwt` (TLS from Apple; full certificate chain verification is deliberately omitted as documented). Returned fields: `productId`, `transactionId`, `originalTransactionId`, `purchaseDate`, `expiresDate`, `environment`, `type`, `inAppOwnershipType`, `revocationDate`, `revocationReason`, `autoRenewStatus`, `autoRenewProductId`, `expirationIntent`, and `status`. Personal identifiers like `appAccountToken` are strictly excluded.
   - Every client function includes Apple documentation reference URLs directly in header comments.
   - Error abstraction: `AppStoreError` categorizes failures as `unavailable` (5xx, 429, timeouts, network) or `rejected` (4xx).
   - Doc-shaped mock fixtures established under `backend/tests/fixtures/appstore/` with `_source` annotations.
3. **Admin API Routes**:
   - Mounted exclusively on `consoleRouter` under `/admin-api/appstore/` (never exposed on public `/api/admin`):
     - `GET /admin-api/appstore/catalog`: caches catalog in memory for 10 minutes; `?refresh=1` query parameter bypasses cache.
     - `GET /admin-api/appstore/transactions/:transactionId?environment=production|sandbox`: validates transaction ID as 1-20 digits; writes an audit trail entry (`appstore.transaction_lookup`) to `admin_audit_log` with `{ transactionId, environment }`. Maps 404 to `notFound`.
   - Error codes added to `docs/error-codes.md`: `appStoreNotConfigured` (503), `appStoreUnavailable` (502), `appStoreRejected` (502).
4. **Console Frontend (`adminFront`)**:
   - Added third navigation rail destination **App Store**.
   - Not-configured state: renders a dedicated information card stating App Store keys are not set, and nothing else.
   - Catalog view: renders subscription groups with tables of subscriptions (Product ID, Name, State, Prices formatted by customer price, currency, and territory) and a Refresh button.
   - Transaction lookup: digits-only text input, Production/Sandbox `SegmentedButton`, "Look up" button, and detailed result card with formatted dates.
   - External links out (open in new tab): App Store Connect subscriptions page (`https://appstoreconnect.apple.com/apps`) and RevenueCat customer search (`https://app.revenuecat.com/customers`).
   - Strict `strings.dart` compliance: zero raw text literals outside `strings.dart` (enforced by `guard_test.dart`).
5. **What the lead's live check must cover**:
   - Replace mock fixtures with real recorded Apple API responses.
   - Verify App Store Connect API team key role and permissions (e.g. App Manager or Admin role is required for subscription catalog endpoints).
   - Test live transaction lookups against Sandbox and Production Apple StoreKit servers with valid store purchase tokens.


