# Backend — Technical Reference

CareCoins backend is a **Node.js REST API** built with Express, connected to PostgreSQL, and integrated with Firebase for authentication and push notifications.

---

## Table of Contents

1. [Tech Stack](#1-tech-stack)
2. [Project Structure](#2-project-structure)
3. [Server Bootstrap](#3-server-bootstrap)
4. [Middleware Stack](#4-middleware-stack)
5. [Authentication (Firebase Admin)](#5-authentication-firebase-admin)
6. [Role-Based Access Control (RBAC)](#6-role-based-access-control-rbac)
7. [Database Layer](#7-database-layer)
8. [API Routes](#8-api-routes)
9. [Services](#9-services)
10. [Push Notifications (FCM)](#10-push-notifications-fcm)
11. [Email (Resend)](#11-email-resend)
12. [File Uploads (Multer)](#12-file-uploads-multer)
13. [Rate Limiting](#13-rate-limiting)
14. [CORS Policy](#14-cors-policy)
15. [Background Jobs](#15-background-jobs)
16. [Infrastructure & Docker](#16-infrastructure--docker)
17. [Testing](#17-testing)
18. [Platform Admin, Registry & Subscriptions](#18-platform-admin-registry--subscriptions)

---

## 1. Tech Stack

| Dependency | Version | Role |
|---|---|---|
| Node.js | ≥ 20 | Runtime (ES Modules, `--watch` for dev) |
| Express | `^4.19` | HTTP framework |
| pg (node-postgres) | `^8.12` | PostgreSQL client with connection pooling |
| firebase-admin | `^12.5` | Firebase ID token verification + FCM server-side push |
| multer | `^2.1` | `multipart/form-data` file uploads |
| express-rate-limit | `^8.3` | Global + per-user rate limiting |
| cors | `^2.8` | CORS whitelist |
| dotenv | `^16.4` | Env var loading |
| resend | `^6.12` | Transactional email (invitation emails) |

**Module system:** ES Modules (`"type": "module"` in `package.json`). All imports use `.js` extensions.

---

## 2. Project Structure

```
backend/
├── src/
│   ├── server.js                  # HTTP server entry point (binds port)
│   ├── app.js                     # Express app (middleware + route mounting)
│   ├── env.js                     # dotenv config (loads .env on startup)
│   │
│   ├── db/
│   │   ├── pool.js                # pg Pool singleton + withTransaction() helper
│   │   ├── schema.sql             # Full database schema (source of truth)
│   │   ├── users.js               # upsertUserFromAuth(), assertActiveMember()
│   │   ├── defaultActivities.js   # Seed data: default activity templates per actor type
│   │   ├── ledgerReasons.js       # payoutReasons(): activity type → coin_ledger reason strings
│   │   └── autoComplete.js        # runAutoCompleteSweep(): auto-award coins for expired approved activities
│   │
│   ├── middleware/
│   │   ├── auth.js                # requireAuth() — Firebase ID token verification
│   │   ├── audit.js               # logLoginHistory() — session audit logging
│   │   ├── rbac.js                # requireRole() + assertMemberRole()
│   │   ├── heartbeat.js           # familyHeartbeat() — touches families.last_active_at
│   │   └── validate.js            # Request body/param validation helpers
│   │
│   ├── routes/
│   │   ├── me.js                  # /api/me — current user, avatar, login events, ledger
│   │   ├── families.js            # /api/families — CRUD, invitations, actors, deletion
│   │   ├── inviteLinks.js         # /api/families/:id/invite-links
│   │   ├── activities.js          # /api/activities — full activity lifecycle
│   │   ├── dashboard.js           # /api/dashboard — family summary data
│   │   ├── marketplace.js         # /api/marketplace — rewards + redemptions
│   │   ├── stats.js               # /api/stats — charts and monthly aggregates
│   │   ├── absences.js            # /api/absences — absence management
│   │   ├── personalTime.js        # /api/personal-time — ask, accept, decline, withdraw
│   │   ├── admin.js               # /api/admin — platform registry, plans, grants
│   │   ├── billing.js             # /api/billing — RevenueCat webhook (shared-secret auth)
│   │   └── events.js              # /api/events — onboarding/telemetry events
│   │
│   ├── services/
│   │   ├── activityService.js     # Activity business logic
│   │   ├── familyService.js       # Family + deletion workflow logic
│   │   ├── memberService.js       # Member, actor, invitation logic
│   │   ├── absenceService.js      # Absences, including the 24 h floor
│   │   ├── personalTimeService.js # Personal-time requests: quote, create, accept, expiry
│   │   ├── distributionService.js # The monthly GDP residual, presence-weighted
│   │   ├── adminService.js        # Platform registry and audit
│   │   ├── entitlementService.js  # Plan + subscription + grant merge
│   │   ├── billingService.js      # RevenueCat event handling
│   │   └── retentionService.js    # Inactive-family retention sweep
│   │
│   └── utils/
│       ├── notify.js              # FCM push notification helpers
│       └── mailer.js              # Resend email helpers
│
├── scripts/
│   ├── init-db.js                 # Run schema.sql + migrations (used by Docker)
│   ├── migrate-fcm.sql            # fcm_tokens table migration
│   ├── migrate-fcm-index.sql      # Index on fcm_tokens
│   ├── migrate-notif-prefs.sql    # notification_preferences table migration
│   └── migrate-deletion.sql       # family_deletion_* tables migration
│
├── tests/
│   ├── activityService.test.js    # Unit tests for activityService
│   └── familyService.test.js      # Unit tests for familyService
│
├── uploads/                       # Disk storage for uploaded avatars
├── Dockerfile
├── package.json
└── .env                           # Environment variables (not committed)
```

---

## 3. Server Bootstrap

**`src/server.js`** imports the Express app and calls `app.listen(PORT)`. This separation keeps the app object importable without binding a port — useful for HTTP-level testing tools like `supertest` if needed in the future. Current tests exercise the service layer directly with mock clients.

**`src/app.js`** assembles the full middleware chain and mounts all routers:

```
Trust proxy (nginx)
↓
CORS
↓
express.json()
↓
Global rate limiter (1 000 req / 15 min per IP)
↓
GET /health                    ← no auth, used by Docker healthcheck
GET /uploads/*                 ← static file serving for uploaded avatars
↓
requireAuth                    ← all /api/* routes below this point
perUserLimiter (300 req / 15 min per UID)
↓
/api/billing       → billingRouter      ← mounted BEFORE requireAuth: the RevenueCat
                                          webhook authenticates by shared secret, not
                                          by Firebase token
↓
requireAuth + perUserLimiter, and familyHeartbeat on every family-scoped router:
/api/admin         → adminRouter        ← additionally behind requireAdmin + adminLimiter
/api/me            → meRouter
/api/families      → familiesRouter
/api/activities    → activitiesRouter
/api/dashboard     → dashboardRouter
/api/marketplace   → marketplaceRouter
/api/stats         → statsRouter
/api/absences      → absencesRouter
/api/personal-time → personalTimeRouter
/api/events        → eventsRouter
↓
Global error handler (500)
```

---

## 4. Middleware Stack

### `middleware/validate.js`

Provides composable validation builders for request bodies and params:

| Helper | What it validates |
|---|---|
| `required()` | Field must be present and non-empty |
| `string(min, max)` | Must be a string within length bounds |
| `positiveInt()` | Must be a number > 0 |
| `isoDate()` | Must parse as a valid ISO 8601 date |
| `oneOf(values)` | Must be one of the allowed string values |
| `email()` | Basic email format check |

Usage:
```js
router.post('/', validateBody({
  title: [required(), string(1, 100)],
  category: [required(), oneOf(['care', 'household'])],
  durationMinutes: [required(), positiveInt()],
}), handler);
```

`validateParams(...names)` validates that URL params are valid positive integers (prevents injection via NaN or negative IDs).

---

## 5. Authentication (Firebase Admin)

**File:** `src/middleware/auth.js`

### `requireAuth(req, res, next)`

Every protected endpoint runs through this middleware. It:

1. Reads the `Authorization: Bearer <token>` header.
2. Returns `401` if no token is present.
3. Calls `admin.auth().verifyIdToken(token)` — validates the JWT signature, expiry, and issuer against Firebase.
4. Populates `req.auth` with `{ uid, email, name }` from the decoded token.
5. Returns `401` on any verification failure.

### Firebase Admin initialization

The admin SDK is initialized lazily on the first call to `requireAuth`. In production it uses **Application Default Credentials** (ADC) — the service account key is mounted into the container at `/run/secrets/firebase-credentials.json` and pointed to by `GOOGLE_APPLICATION_CREDENTIALS`. In the emulator (`FIREBASE_AUTH_EMULATOR_HOST` set), no credentials are needed — tokens are verified locally.

### `deleteFirebaseUser(uid)`

Called from `DELETE /api/me` to remove the user from Firebase Auth as part of the account deletion flow.

### User upsert pattern

`req.auth` contains the Firebase UID but not the internal database ID. Every protected handler calls `upsertUserFromAuth(client, req.auth)` at the start:

```js
// src/db/users.js
export async function upsertUserFromAuth(client, auth) {
  // UPDATE-first: handles returning users and email/name changes.
  const { rows: updated } = await client.query(
    `UPDATE users
     SET email        = COALESCE($2, email),
         display_name = COALESCE($3, display_name)
     WHERE firebase_uid = $1
     RETURNING id, firebase_uid, email, display_name, avatar_url`,
    [auth.uid, auth.email, auth.name]
  );
  if (updated.length) return updated[0];

  // New user — insert, with conflict on email to handle invited users signing up.
  const { rows } = await client.query(
    `INSERT INTO users (firebase_uid, email, display_name)
     VALUES ($1, $2, $3)
     ON CONFLICT (email)
     DO UPDATE SET firebase_uid  = EXCLUDED.firebase_uid,
                   display_name  = COALESCE(EXCLUDED.display_name, users.display_name)
     RETURNING id, firebase_uid, email, display_name, avatar_url`,
    [auth.uid, auth.email, auth.name]
  );
  return rows[0];
}
```

This ensures the user row always exists before any business logic runs, and keeps email/display_name in sync with Firebase without a separate sync job. The UPDATE-first pattern also handles the case where an invited user (already in the DB by email) signs up via Firebase for the first time.

---

## 6. Role-Based Access Control (RBAC)

**File:** `src/middleware/rbac.js`

### Role hierarchy

```
caregiver (level 2)  ←  full family management
member    (level 1)  ←  task completion, coin spending
```

A caregiver has all member permissions plus: create/approve/delete activities, manage invitations, create rewards, manage actors, request family deletion.

### `requireRole(role, getFamilyId)` — Express middleware

Used directly in route definitions when `familyId` is available in the request params, body, or query:

```js
router.delete('/:familyId',
  requireRole('caregiver', r => r.params.familyId),
  handler
);
```

Internally:
1. Extracts `familyId` using the provided getter function.
2. Queries `family_members` for `(family_id, user_id, status = 'active')`.
3. Returns `403` if the user is not a member or does not meet the required role level.

### `assertMemberRole(client, userId, familyId, role)` — in-transaction helper

Used inside `withTransaction` callbacks when `familyId` is derived from a prior DB query (not from the request):

```js
const rbacErr = await assertMemberRole(client, user.id, act.family_id, 'caregiver');
if (rbacErr) return rbacErr; // { error: { code, message } }
```

Returns `null` on success, `{ error: { code, message } }` on failure. The route handler converts the error object to the appropriate HTTP response.

---

## 7. Database Layer

### Connection pool — `src/db/pool.js`

A single `pg.Pool` instance is shared across the whole application:

```js
export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
});
```

### `withTransaction(fn)` helper

All write operations use this helper to guarantee atomicity:

```js
export async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
```

Read-only queries use `pool.query()` directly (no transaction overhead).

### Schema initialization

`scripts/init-db.js` runs on container startup (`db-init` Docker service):
1. Executes `schema.sql` (idempotent — all `CREATE TABLE IF NOT EXISTS`).
2. Runs each migration SQL file in order to add tables/columns introduced after the initial schema.

The migration files are:
- `migrate-fcm.sql` — `fcm_tokens` table (push token registration).
- `migrate-fcm-index.sql` — `idx_fcm_tokens_user_id` index on `fcm_tokens(user_id)`.
- `migrate-notif-prefs.sql` — `notification_preferences` table.
- `migrate-deletion.sql` — `family_deletion_requests` and `family_deletion_approvals` tables.

---

## 8. API Routes

All routes are prefixed with `/api` and require a valid Firebase Bearer token unless noted.

### `GET /health`
No auth. Returns `{ status: 'ok', service: 'carecoins-backend' }`. Used by Docker healthcheck and load balancers.

---

### `/api/me` — Current User

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/me` | any | Current user profile + all family memberships + actors |
| PATCH | `/api/me/profile` | any | Update display name, email, alias |
| POST | `/api/me/avatar` | any | Upload profile avatar (multipart, max 2 MB) |
| DELETE | `/api/me` | any | Soft-delete account + cancel future activities + delete Firebase user |
| POST | `/api/me/login-event` | any | Record login in `login_history`; returns `eventId` |
| POST | `/api/me/logout-event` | any | Close open `login_history` session by `eventId` |
| GET | `/api/me/login-history` | any | Last 20 login events (IP, user agent, timestamps) |
| GET | `/api/me/invites` | any | Pending email invitations matching this user's email |
| GET | `/api/me/ledger` | any | Coin ledger for `familyId` + `month` (YYYY-MM) |
| POST | `/api/me/fcm-token` | any | Register FCM push token (upsert by token) |
| DELETE | `/api/me/fcm-token` | any | Remove FCM push token |
| GET | `/api/me/notification-preferences` | any | Load per-category notification preferences |
| PUT | `/api/me/notification-preferences` | any | Save per-category notification preferences |

---

### `/api/families` — Family Management

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/families` | any | List all families this user belongs to (active status) |
| POST | `/api/families` | any | Create a new family; creator becomes first caregiver |
| GET | `/api/families/:id/budget` | member | Current month's coin budget and distribution status |
| POST | `/api/families/join-request` | any | Accept an email invitation (creates pending membership) |
| POST | `/api/families/join-by-token` | any | Join via invite link UUID token |
| GET | `/api/families/:id/members` | member | List all members with roles and coin balances |
| POST | `/api/families/:id/members/:uid/approve` | caregiver | Approve a pending member |
| PATCH | `/api/families/:id/members/:uid/role` | caregiver | Change member role (caregiver ↔ member) |
| GET | `/api/families/:id/invitations` | member | List all email invitations |
| POST | `/api/families/:id/invitations` | caregiver | Send email invitation |
| POST | `/api/families/:id/actors` | caregiver | Add a non-user actor (object of care) |
| DELETE | `/api/families/:id/actors/:aid` | caregiver | Remove an actor |
| POST | `/api/families/:id/actors/:aid/avatar` | caregiver | Upload actor avatar (multipart) |
| DELETE | `/api/families/:id` | caregiver | Request or execute family deletion |
| GET | `/api/families/:id/deletion-requests` | caregiver | List active deletion requests |
| POST | `/api/families/:id/deletion-requests/:rid/approve` | caregiver | Vote to approve deletion |
| POST | `/api/families/:id/deletion-requests/:rid/reject` | caregiver | Vote to reject deletion |
| GET | `/api/families/:id/invite-links` | caregiver | List all invite links |
| POST | `/api/families/:id/invite-links` | caregiver | Generate new invite link (optional expiry/max-uses) |
| DELETE | `/api/families/:id/invite-links/:lid` | caregiver | Revoke an invite link |

---

### `/api/activities` — Activity Lifecycle

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/activities?familyId=` | member | List all activities for a family |
| POST | `/api/activities` | member | Create a new activity template |
| POST | `/api/activities/:id/approve` | caregiver | Approve a pending activity |
| POST | `/api/activities/:id/schedule` | caregiver | Schedule an approved activity (set `starts_at`) |
| POST | `/api/activities/:id/recurrence` | caregiver | Generate recurrence instances (daily/weekdays/weekly) |
| POST | `/api/activities/:id/complete` | assignee | Mark activity as completed |
| POST | `/api/activities/:id/validate` | caregiver | Validate completion; credit coins to assignee |
| POST | `/api/activities/:id/revert` | assignee | Undo a completion before validation |
| POST | `/api/activities/:id/bounty` | caregiver | Offer a coin bounty on an activity |
| POST | `/api/activities/:id/accept-bounty` | member | Accept a bounty (take over the activity) |
| PATCH | `/api/activities/:id/time` | assignee or caregiver | Move an upcoming activity to `startsAt`, keeping its duration. Coverage never moves on its own; personal time only by its owner and not once covered. Checks the assignee's absences and overlaps (coverage exempt) |
| DELETE | `/api/activities/:id` | creator/caregiver | Delete single instance or full series (`?series=true`) |

---

### `/api/dashboard` — Family Dashboard

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/dashboard/:familyId` | member | Aggregated summary: member balances, activity counts, recent completions, KPIs |

---

### `/api/marketplace` — Rewards

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/marketplace/rewards/:familyId` | member | Active, available rewards + recent redemptions |
| POST | `/api/marketplace/rewards` | caregiver | Create a new reward |
| POST | `/api/marketplace/rewards/:id/redeem` | member | Redeem a reward (atomic: debit coins + insert redemption) |

---

### `/api/stats` — Statistics

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/stats/:familyId` | member | Every aggregate the stats screen draws, in one payload. The route takes no month parameter: the month-grouped blocks (`trendByMonth`, `coinFlowByReason`, `fairnessByMonth`) carry a `YYYY-MM` column and the client picks from them |

**Blocks returned:** `kpis`, `activeCaregivers`, `trendByMonth`, `typeSplit`,
`activityFrequency`, `memberBalances`, `bountyStats`, `rewardsByUser`, `topRewards`,
`completionRates`, `statusDistribution`, `coinFlowByReason`, `fairnessByMonth`.

`fairnessByMonth` sets personal time taken against coverage given, per member and month —
`personal_minutes` / `personal_count` from `category = 'self'`, `coverage_minutes` /
`coverage_count` from `type = 'coverage'`, both over completed rows only. Every care
aggregate filters `category = 'care'`, so personal time never inflates a contribution figure.
There is deliberately **no declined count in this payload, and there must never be one**:
declining has to stay free and invisible, or the sweetener becomes social pressure.

---

### `/api/absences` — Absences

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/absences?familyId=` | member | List all absences for a family |
| POST | `/api/absences` | caregiver | Create an absence record |
| DELETE | `/api/absences/:id` | caregiver | Delete an absence |

---

### `/api/personal-time` — Personal Time & Coverage

Booking time for yourself always carries a coverage offer to another caretaker, and is only
real once they accept. Nothing is scheduled while a request is pending.

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/personal-time?familyId=` | member | List the family's requests. **Also sweeps expired ones**, refunding their escrow |
| POST | `/api/personal-time/quote` | member | Price a window before committing: baseline, your balance, the counterparty's conflicts, the candidate list, and the occurrence count for a repeat |
| POST | `/api/personal-time` | member | Ask. Escrows `sweetener × occurrences` up front; refuses and writes nothing if unaffordable |
| POST | `/api/personal-time/:id/accept` | caregiver | Materialize a pair per occurrence, skipping any neither side can make and refunding those. Returns `{ created, skipped, refunded }` |
| POST | `/api/personal-time/:id/decline` | caregiver | Refund the whole escrow, book nothing |
| DELETE | `/api/personal-time/:id` | member | The requester withdraws; escrow refunded |

**Body fields on create:** `familyId`, `title`, `type` (one of `sport`, `social`, `rest`,
`appointment`, `other`), `description`, `startsAt`, `endsAt`, `requestedOf` (null = ask
anyone), `coverageNeeded`, `sweetenerCoins` (per occurrence), `recurrence` (`daily`,
`weekdays`, `weekly`), `recurrenceUntil`.

The window must be 15 minutes to 24 hours — beyond a day it is an absence, which nobody gets
to decline. A repeat is capped at 60 occurrences and **refused** rather than truncated, since
a series quietly cut short would escrow for fewer favours than the requester believed they
were asking.

---

## 9. Services

Services contain all business logic. Routes are kept thin — they validate input, call a service, and map the result to an HTTP response. Services return `{ data }` on success or `{ error: { code, message } }` on domain errors (not thrown — returned as values so the route can produce the correct HTTP status without a try/catch per check).

### `activityService.js`

| Function | Description |
|---|---|
| `listActivities(client, userId, familyId)` | Returns all activities for the family, asserting membership |
| `createActivity(client, userId, payload)` | Inserts activity template; asserts membership |
| `approveActivity(client, userId, activityId)` | Sets status to `approved`; asserts caregiver role on the activity's family |
| `scheduleActivity(client, userId, activityId, startsAt)` | Sets `starts_at`/`ends_at`; if `startsAt` is in the past, sets status to `pending_validation` |
| `createRecurrence(client, userId, instanceId, { frequency, untilDate })` | Generates and inserts repeated instances from a template up to `untilDate` |
| `completeActivity(client, userId, instanceId)` | Sets status to `pending_validation` (awaits caregiver validation) |
| `validateActivity(client, userId, activityId)` | Sets status to `completed`; credits `coin_value + bounty_amount` to the assignee via `coin_ledger` and updates `family_members.coin_balance` |
| `revertActivity(client, userId, activityId)` | Undoes a `completed` activity (status → `rejected`): debits the payout and **appends** `*_reverted` rows to `coin_ledger` — the original credit is never rewritten — and refunds any bounty to its offerer |
| `offerBounty(client, userId, activityId, amount)` | Sets `bounty_amount` and `bounty_offered_by` |
| `acceptBounty(client, userId, activityId)` | Reassigns the activity to the accepting user |
| `deleteActivity(client, userId, activityId, isSeries)` | Deletes a single instance or all instances sharing the same template root |

### `familyService.js`

| Function | Description |
|---|---|
| `listFamilies(client, userId)` | Returns all active family memberships |
| `createFamily(client, user, payload)` | Creates family + seeds default activity templates + inserts creator as caregiver |
| `getFamilyBudget(client, userId, familyId)` | Returns `monthlyBudget`, `usedThisMonth`, `remainingBudget`, and `baseRatePerHour` (budget ÷ 720 hours/month) |
| `deleteFamily(client, user, familyId)` | If sole caregiver: deletes immediately. If multiple caregivers: creates a `family_deletion_request` and notifies |
| `getDeletionRequests(client, familyId)` | Lists open deletion requests with per-caregiver vote status |
| `approveDeletion(client, userId, familyId, requestId)` | Records approval; if all caregivers approved, deletes the family |
| `rejectDeletion(client, userId, familyId, requestId)` | Records rejection; marks the request as rejected |

### `memberService.js`

| Function | Description |
|---|---|
| `joinByInvitation(client, user, { familyId, alias })` | Creates a `pending` membership matched against a valid email invitation |
| `joinByToken(client, user, { token, alias })` | Validates invite link (not revoked, not expired, within max-uses); creates `active` membership; increments `uses` |
| `approveMember(client, familyId, userId)` | Sets membership status from `pending` to `active` |
| `updateMemberRole(client, familyId, userId, role)` | Changes role; blocks demoting the last caregiver |
| `listMembers(client, userId, familyId)` | Returns all members with balances and pending actors |
| `listInvitations(client, userId, familyId)` | Returns all pending invitations |
| `createInvitation(client, user, familyId, { email, name })` | Inserts invitation; enforces unique `(family_id, email)` |
| `addActor(client, familyId, payload)` | Inserts a non-user actor |
| `removeActor(client, familyId, actorId)` | Deletes an actor — only `actor_type = 'pet'` is allowed; returns 403 for any other type. Also decreases `families.monthly_coin_budget` by 720 (full-time) or 360 (part-time) |
| `updateActorAvatar(client, familyId, actorId, avatarUrl)` | Updates `avatar_url` on an actor |

---

## 10. Push Notifications (FCM)

**File:** `src/utils/notify.js`

The backend sends push notifications server-side using the **Firebase Admin SDK's `messaging.sendEachForMulticast()`**.

### Three notification targeting functions

| Function | Target |
|---|---|
| `notifyUser(userId, payload)` | A single user (all their registered devices) |
| `notifyFamilyCaregivers(familyId, excludeUserId, payload)` | All active caregivers in a family, excluding one (e.g. the actor) |
| `notifyFamilyAll(familyId, excludeUserId, payload)` | All active members in a family, excluding one |

### FCM token management

- Tokens are stored in the `fcm_tokens` table (registered via `POST /api/me/fcm-token`).
- Each function queries `fcm_tokens` joined with `family_members` to get the correct set of device tokens.
- A `notification_preferences` LEFT JOIN filters out users who opted out of that notification category.
- After sending, any tokens that Firebase reports as invalid or unregistered are **pruned** from the DB automatically (`pruneStale()`).

### Payload structure

```js
{
  tokens: [...],
  notification: { title, body },
  webpush: {
    notification: { icon: '/icon-192.png', badge: '/icon-192.png' },
    fcmOptions: { link: url },   // deep-link on notification tap
  },
  data: { url },                 // also in data for SW access
}
```

### Notification events triggered by each route

| Trigger | Function used | prefKey |
|---|---|---|
| New activity created | `notifyFamilyCaregivers` | `activity_assigned` |
| Activity scheduled (with assignee) | `notifyUser` (assignee) | `activity_assigned` |
| Activity in past → needs validation | `notifyFamilyCaregivers` | `activity_assigned` |
| Activity completed | `notifyFamilyAll` | `activity_completed` |
| Activity validated | `notifyUser` (assignee) | `activity_validated` |
| Bounty offered | `notifyFamilyAll` | `bounty_offered` |
| Member joined (invitation) | `notifyFamilyCaregivers` | `family_events` |
| Member joined (invite link) | `notifyFamilyCaregivers` | `family_events` |
| Family deletion requested | `notifyFamilyCaregivers` | `family_events` |

---

## 11. Email (Resend)

**File:** `src/utils/mailer.js`

Sends transactional emails using **Resend**. Currently used for email invitations only:

```js
sendInvitationEmail({
  toEmail,     // recipient address
  toName,      // recipient name (optional)
  inviterName, // name of the caregiver who sent the invite
  familyName,  // name of the family
})
```

Email sending is fire-and-forget (`.catch` logs errors but does not fail the HTTP response) — a failed email does not block the invitation from being created in the database.

---

## 12. File Uploads (Multer)

**User avatars** — `POST /api/me/avatar`
- Storage: disk, `backend/uploads/users/<firebase_uid>/avatar.<ext>`
- Allowed MIME types: `image/jpeg`, `image/png`, `image/webp`
- Max size: 2 MB
- Filename is always `avatar.<ext>` (overwriting the previous avatar for that user)

**Actor avatars** — `POST /api/families/:id/actors/:aid/avatar`
- Storage: disk, `backend/uploads/families/<familyId>/actors/<actorId>/avatar.<ext>`
- Same MIME and size restrictions
- Directory is created with `fs.mkdirSync({ recursive: true })` on first upload

Uploaded files are served as static assets via `GET /uploads/*` (Express `static` middleware). In production, nginx proxies `/uploads/*` to the backend container.

**Security:**
- MIME type is validated by checking `file.mimetype` (not just the file extension).
- Family ID and Actor ID are parsed as integers before being used as path segments (`String(Number(id))`) to prevent path traversal.
- File names are normalized to `avatar.<ext>` — user-supplied filenames are never used.

---

## 13. Rate Limiting

Two limiters are applied via `express-rate-limit`:

### Global limiter (IP-based)
- **Window:** 15 minutes
- **Limit:** 1 000 requests per IP
- Applied to all routes (including `/health`)
- Uses `trust proxy: 1` so the real client IP is read from `X-Forwarded-For` (set by nginx)

### Per-user limiter (UID-based)
- **Window:** 15 minutes
- **Limit:** 300 requests per Firebase UID
- Applied only to `/api/*` routes (after `requireAuth`, so `req.auth.uid` is guaranteed to be set)
- Prevents a single authenticated user from overwhelming the API even if they rotate IPs

Both limiters use standard headers (`RateLimit-*`) and return:
```json
{ "error": "Too many requests. Please try again later." }
```

---

## 14. CORS Policy

The allowed origins list is read from the `ALLOWED_ORIGINS` environment variable (comma-separated). Defaults to `http://localhost:5173` if not set.

```js
app.use(cors({
  origin: function (origin, callback) {
    if (!origin) return callback(null, NODE_ENV !== 'production'); // allow server-to-server in dev
    if (ALLOWED_ORIGINS.includes(origin)) return callback(null, true);
    callback(new Error(`Origin ${origin} not allowed by CORS policy.`));
  },
  credentials: true
}));
```

In production (Docker), the backend is not exposed to the internet. Nginx terminates public requests and proxies to the backend on the internal network, so CORS is only relevant for local development.

---

## 15. Background Jobs

### `runAutoCompleteSweep(client, familyId)` — `src/db/autoComplete.js`

This is a transactional utility function (not a standalone script) called from within an existing database transaction. It sweeps activities for a given family and:

1. Finds all activities with `status = 'approved'` and `ends_at <= NOW()` (locked with `FOR UPDATE`).
2. Sets each to `status = 'completed'` and clears any bounty.
3. Credits `coin_value + bounty_amount` to the assignee's `family_members.coin_balance`.
4. Inserts corresponding `coin_ledger` entries with reasons `activity_completed` and `bounty_earned`.

This function is called from routes/services that need to eagerly resolve expired activities before returning data (e.g., when loading the activity list).

**Monthly coin distribution** logic lives in `familyService.js`. The `last_coin_distribution_month` column in `families` acts as an idempotency guard — distribution only runs once per `YYYY-MM`. This can be triggered manually or hooked into a scheduled job.

---

## 16. Infrastructure & Docker

The entire stack is described in `docker-compose.yml`:

```
postgres:16          — database, no public ports, internal network only
  └── db-init        — runs once: npm run db:init (schema + migrations)
       └── backend   — Node.js API, no public ports
            └── frontend — nginx serving SPA + proxying /api and /uploads, port 80
```

### Service details

**postgres**
- Image: `postgres:16`
- Data persisted in a named volume `pgdata`
- Healthcheck: `pg_isready -U carecoins -d carecoins`

**db-init**
- Runs `npm run db:init` which executes `scripts/init-db.js`
- Exits after completion (`service_completed_successfully`)
- Backend depends on this completing before starting

**backend**
- `GOOGLE_APPLICATION_CREDENTIALS` points to a mounted Firebase credentials JSON
- `uploads/` directory is bind-mounted so avatars persist across container restarts
- `NODE_ENV=production` — disables Firebase emulator mode

**frontend**
- Multi-stage build: Node.js build stage → nginx serving stage
- All `VITE_*` env vars are injected as Docker build args at image build time (baked into the JS bundle)
- nginx proxies `/api/*` and `/uploads/*` to the backend container hostname `backend:3000`
- Exposes port 80 — receives Cloudflare traffic

---

## 17. Testing

### Unit tests (Node.js built-in test runner)

Run with `npm test` (uses `node --test`). Tests run with `--test-concurrency=1` for deterministic ordering.

**`tests/activityService.test.js`**
- Tests the full activity lifecycle using a mock DB client (no real database required).
- Covers: complete, validate, revert, bounty, accept-bounty, list activities.
- Each test builds a `mockClient(responses)` that replays pre-defined query results in order, letting tests assert both the return value and the SQL calls made.

**`tests/familyService.test.js`**
- Tests family creation, member join (by invitation and by token), role changes, actor removal, and deletion workflows.
- Also uses mock DB clients — no real database or `.env.test` needed.

### E2E tests

There is no automated end-to-end layer (see `docs/automatic-testing-E2E.md`). For manual
full-stack runs, `npm run dev:test` starts the backend against the Firebase Auth Emulator
(`localhost:9099`) with `NODE_ENV=test` and `FIREBASE_AUTH_EMULATOR_HOST` set.

---

## 18. Platform Admin, Registry & Subscriptions

Added per `docs/admin-family-management-plan.md` (Phases 1–3, 5, 6). Full
design rationale and implementation log live in that document; this section
is the operational reference.

### Identity & authorization

- `users.platform_role` (`'user'` | `'admin'`) is a **global axis, separate
  from family roles** — an admin gains no rights inside any family.
  Promotion is CLI-only: `node scripts/promote-admin.js <email> [--demote]`.
- `requireAdmin` (in `src/middleware/rbac.js`) guards `/api/admin`, mounted
  as `requireAuth → adminLimiter (100 req/15 min per UID) → requireAdmin`.
  The DB is authoritative; nothing client-side is trusted.
- Every mutating admin call writes one `admin_audit_log` row in the same
  transaction (`logAdminAction` in `src/services/adminService.js`).

### Privacy boundary

Admin endpoints expose **registry aggregates and billing state only** —
never member identities, activities, coins or rewards, and never raw
billing-provider payloads. `adminService` maps rows through explicit field
allowlists, and `tests/adminRegistry.test.js` feeds contaminated rows to
assert nothing else can leak (CI fails otherwise).

### Family heartbeat

`families.last_active_at` is touched by the `familyHeartbeat` middleware
(`src/middleware/heartbeat.js`) on **successful** family-scoped responses
only, throttled in-memory to one write per family per hour, and not mounted
on `/api/admin`. Buckets: active ≤ 30 days, dormant 30–90, inactive > 90.

### Admin endpoints

| Endpoint | Purpose |
|---|---|
| `GET /api/admin/status` | Self-check for the Flutter admin console gate |
| `GET /api/admin/families?search=&status=&page=&pageSize=` | Paged registry (name/ID search, heartbeat-bucket filter) |
| `GET /api/admin/families/:id` | Registry detail + pending/actor counts |
| `POST /api/admin/families/:id/notify-inactive` | Push nudge to caregivers via `notifyFamilyCaregivers` (identities never shown to the admin); audited |
| `GET /api/admin/plans` · `POST /api/admin/plans` · `PATCH /api/admin/plans/:code` | Plan catalog CRUD; audited |
| `GET /api/admin/families/:id/billing` | Subscription state + grants + billing-event metadata |
| `POST /api/admin/families/:id/grants` · `DELETE …/grants/:grantId` | Comp/trial grants; revocation stamps `revoked_at`; audited |

### Entitlements

`src/services/entitlementService.js`:

- `getFamilyEntitlements(client, familyId)` merges the default plan, the
  subscription (only while `trialing`/`active`/`in_grace`) and unrevoked,
  unexpired admin grants — **most generous wins** (absent limit key =
  unlimited; features are ON if any source grants them).
- `limitWarning(...)` implements the soft rollout: choke points
  (member approve/join, actor add, reward create) attach
  `member_limit_exceeded` / `actor_limit_exceeded` /
  `reward_limit_exceeded` warnings to successful responses.
- `assertFamilyWritable(client, familyId)` returns a 402 error object when
  `family_plans.status = 'past_due'`; called **before** mutations
  (`withTransaction` only rolls back on throw). Other lapsed statuses
  downgrade gracefully to the default plan instead of blocking writes.

### Billing (RevenueCat)

- `POST /api/billing/webhook` — mounted **without** `requireAuth`;
  authenticated by `REVENUECAT_WEBHOOK_SECRET` matching the webhook's
  Authorization header configured in the RevenueCat dashboard. Idempotent
  via `billing_events.event_id`; events are normalized into `family_plans`
  by `src/services/billingService.js` (INITIAL_PURCHASE/RENEWAL/… → active,
  CANCELLATION → canceled but entitled until `current_period_end`,
  EXPIRATION → expired, BILLING_ISSUE → in_grace, NON_RENEWING_PURCHASE =
  lifetime → active with no period end).
- Family attribution: the Flutter app sets a `family_id` **subscriber
  attribute** before opening the paywall; the webhook reads it. Events
  without it are logged unprocessed for follow-up.
- `GET /api/families/:id/entitlements` — member-accessible; the single
  place every client reads the family's plan from (drives the Pro section
  in the app and the double-purchase guard). Clients never trust store SDK
  state for family-wide entitlements.

### Retention sweep

`node scripts/retention-sweep.js [--apply] [--inactive-days=365] [--notice-days=30]`
— deletes families that are both long-inactive **and** were sent an
inactivity notice that went unanswered. Dry-run by default; the DELETE
re-verifies inactivity so a family that returned is skipped; the audit row
is attributed to the admin whose notice started the process
(`src/services/retentionService.js`, `tests/retention.test.js`).

### Tests

`tests/adminFoundation.test.js`, `tests/adminRegistry.test.js`,
`tests/entitlements.test.js`, `tests/retention.test.js` — mock-client style,
same as the rest of the suite.
