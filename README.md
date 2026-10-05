# CareCoins — Architecture & System Description

CareCoins is a family caregiving coordination app. It uses a coin reward system to make household and caregiving contributions visible and valued across a family unit, so the person who always does everything finally has a record.

**Stack:** Flutter (iOS · Android · web, in `fluterFront/`) · Node.js / Express · PostgreSQL 16 · Firebase Auth + FCM · RevenueCat (in-app subscriptions) · Docker

Localized in **English, Spanish, French and German**. The app ships as native store builds and as an installable PWA on web.

---

## Table of contents

1. [Frontend (Flutter)](#part-1-frontend-flutter)
2. [Backend](#part-2-backend)
3. [Database schema](#part-3-database-schema)
4. [Platform admin & subscriptions](#part-4-platform-admin--subscriptions)
5. [Onboarding & starter tasks](#part-5-onboarding--starter-tasks)
6. [Push notifications](#part-6-push-notifications)
7. [Activity lifecycle](#part-7-activity-lifecycle)
8. [Automated tests](#part-8-automated-tests)
9. [Local development](#part-9-local-development)
10. [Documentation index](#part-10-documentation-index)

---

## Part 1: Frontend (Flutter)

Single Dart codebase targeting iOS, Android and web. State is a single `ChangeNotifier` (`AppState`) provided with `provider`; there is no router package — the shell swaps tabs and screens push with `MaterialPageRoute`.

### Design system

Tokens live in `lib/theme/app_theme.dart` (see `docs/DESIGN.md`).

- **Typeface:** Plus Jakarta Sans (500 / 700 / 800) via `google_fonts`. Hierarchy through weight and size only.
- **Colour palette:** semantic-only. Blue `#2563EB` = action, green `#16A34A` = done, amber `#D97706` = household, red `#DC2626` = danger. Each colour has one job.
- **Radius tokens:** `sm` 8 · `md` 16 · `lg` 24 · `pill` 999.
- **Accessibility:** WCAG AA contrast minimum, 44×44 touch targets, reduced-motion support, status never conveyed by colour alone.

### Screens (`lib/screens/`)

| File | Purpose |
|---|---|
| `shell.dart` | Root layout: desktop pill nav, mobile bottom tabs, global toasts, FCM sync, badge clearing |
| `landing_screen.dart` | Brand/acquisition surface for signed-out visitors, with an animated product demo |
| `login_screen.dart` | Email/password and Google sign-in |
| `onboarding_screen.dart` | Four-step create-family wizard + join by invite link/token (see [Part 5](#part-5-onboarding--starter-tasks)) |
| `dashboard_screen.dart` | Family hub: member grid, KPIs, week strip, bounties, absences, activation checklist |
| `daily_screen.dart` | Signature daily timeline: NOW divider, gap indicators, day swipe, complete/revert, bounty banners, **personal-time requests** |
| `activities_screen.dart` | Activity template library, creation with budget-based coin suggestion, budget health |
| `marketplace_screen.dart` | Reward store: browse, redeem, history, create |
| `stats_screen.dart` | Charts: coin flow, hours per member and category, completion rates, ledger, **personal time taken vs. coverage given** |
| `profile_screen.dart` | Account settings, notification prefs, language picker, family circle, wallet, **Pro subscription**, **admin entry** |
| `admin_screen.dart` | Platform admin console — family registry, plan catalog, billing & grants ([Part 4](#part-4-platform-admin--subscriptions)) |

### Widgets, services and data (`lib/`)

- **`widgets/ui.dart`** — the design-system kit: `VCard`, `VButton`, `VInput`, `KpiCard`, `PillBadge`, `SegmentedTabs`, `Tappable`, `EmptyState`, `LoadErrorState`, `PageHeading`, `AvatarCircle`, `AssigneeBadge`.
- **`widgets/`** — `family_circle.dart` (dependents, invites, QR), `charts.dart`, `absence_dialog.dart`, `personal_time_dialog.dart` (ask for personal time: window, repeat, who to ask, sweetener), `help_sheet.dart`, `coach_marks.dart` + `activation_checklist.dart` (guided onboarding), `subscription_card.dart` (MyCareCoins Pro).
- **`services/api_client.dart`** — thin REST client: JSON in/out, Bearer token, timeouts, and typed `ApiException`s localized at the display boundary.
- **`services/purchase_service.dart`** — RevenueCat SDK wrapper: configure, identity sync, paywall, Customer Center, restore. No-ops on web.
- **`services/push_service.dart`** — FCM token lifecycle (register on enable, silent refresh on startup, remove on disable) and foreground message handling.
- **`services/telemetry.dart`**, **`services/tour_service.dart`** — onboarding instrumentation and the guided tour.
- **`state/app_state.dart`** — auth session, `/api/me` payload, current family, locale, toasts, `isCaregiver` / `isPlatformAdmin`.
- **`data/starter_packs.dart`** — the localized starter-task catalogue ([Part 5](#part-5-onboarding--starter-tasks)).
- **`l10n/app_*.arb`** — 787 keys × 4 languages, compiled by `flutter gen-l10n`. `untranslated.json` must be empty before release (see `docs/i18n-plan.md`).

### PWA (web build)

Installable with a standalone manifest, custom icons and brand theme colour. `firebase-messaging-sw.js` handles background push, sets the app badge, and deep-links on tap via each notification's `data.url`.

---

## Part 2: Backend

Express REST API behind Firebase Auth middleware and rate limiters. PostgreSQL via `pg` pool; every mutation runs inside `withTransaction` for atomicity.

### Service layer (`src/services/`)

Business logic is separated from HTTP routing. Each function receives a DB `client` already inside a transaction and returns `{ data }` or `{ error: { code, message } }`, so it is testable without HTTP.

| Service | Responsibilities |
|---|---|
| `activityService.js` | `listActivities`, `createActivity`, `approveActivity`, `scheduleActivity`, `createRecurrence`, `completeActivity`, `validateActivity`, `offerBounty`, `acceptBounty`, `deleteActivity`, `revertActivity` |
| `familyService.js` | `listFamilies`, `getFamilyBudget`, `createFamily`, `deleteFamily`, `getDeletionRequests`, `approveDeletion`, `rejectDeletion` |
| `memberService.js` | `listMembers`, `listInvitations`, `createInvitation`, `approveMember`, `updateMemberRole`, `joinByInvitation`, `joinByToken`, `addActor`, `removeActor`, `updateActorAvatar` |
| `adminService.js` | Family registry (aggregates only), plan catalog CRUD, family billing view, admin grants, `logAdminAction` audit helper |
| `entitlementService.js` | `getFamilyEntitlements` (merges default plan + subscription + grants), `limitWarning`, `assertFamilyWritable` |
| `billingService.js` | RevenueCat webhook normalization into `family_plans`, idempotent via `billing_events.event_id` |
| `retentionService.js` | Finds and deletes families that were noticed as inactive and stayed silent |
| `absenceService.js` | Absence CRUD and the **24 h floor** — below a day it is personal time, not time off |
| `personalTimeService.js` | Personal-time requests: `quoteRequest`, `createRequest`, `acceptRequest`, `declineRequest`, `cancelRequest`, `expireStaleRequests`, plus the pure rules `validateSelfWindow`, `priceCoverage`, `expiryFor`, `occurrencesFor` |
| `distributionService.js` | The monthly GDP residual, presence-weighted so an absent caretaker's share goes to whoever was home |

### Middleware (`src/middleware/`)

- **`auth.js`** (`requireAuth`) — verifies the Firebase ID token; supports the Auth Emulator via `FIREBASE_AUTH_EMULATOR_HOST`. Exposes `uid`, `email`, `name`, `authTime`.
- **`rbac.js`** — `requireRole` / `assertMemberRole` for family roles, and `requireAdmin` / `checkPlatformAdmin` for the platform-admin axis (deliberately separate — see [Part 4](#part-4-platform-admin--subscriptions)).
- **`heartbeat.js`** — touches `families.last_active_at` on successful family-scoped responses, throttled to one write per family per hour.
- **`validate.js`** — composable body/param rules (`required`, `string`, `positiveInt`, `isoDate`, `oneOf`, `email`).
- **`audit.js`** — login-history recording.

### Utilities & DB helpers

- **`utils/notify.js`** — FCM helpers `notifyUser`, `notifyFamilyCaregivers`, `notifyFamilyAll`; each takes a `prefKey` filtering opted-out users. Stale tokens pruned after failed sends.
- **`utils/mailer.js`** — Resend email for invitations; logs to console when `RESEND_API_KEY` is unset.
- **`db/pool.js`** — pool + `withTransaction` (BEGIN / COMMIT / ROLLBACK; rolls back only on throw).
- **`db/users.js`** — `upsertUserFromAuth`, `assertActiveMember`.
- **`db/autoComplete.js`** — sweeps past-due approved activities to completed and pays out atomically.
- **`db/defaultActivities.js`** — `insertStarterTasks` + `validateStarterTasks` for client-supplied catalogues, and the legacy English `insertDefaultActivities` fallback.

### API routes

#### `/api/me` — personal & account
| Method | Path | Description |
|---|---|---|
| GET | `/` | Current user (incl. `platform_role`), families, pending requests, actors |
| PATCH | `/profile` | Update display name, email, family alias |
| POST | `/avatar` | Upload avatar (JPEG/PNG/WebP, max 2 MB) |
| GET | `/invites` | Pending email invitations |
| GET | `/login-history` | Last 20 login events |
| GET | `/ledger` | Monthly coin ledger |
| POST | `/login-event` · `/logout-event` | Session tracking |
| POST · DELETE | `/fcm-token` | Register / remove push token |
| GET · PUT | `/notification-preferences` | Per-category opt-in (5 flags) |
| DELETE | `/` | Delete account (anonymise, cancel activities, remove Firebase user) |

#### `/api/families` — family management
| Method | Path | Description |
|---|---|---|
| GET · POST | `/` | List / create family (budget from care hours; seeds starter tasks) |
| DELETE | `/:familyId` | Request deletion (unanimous caregiver approval) |
| GET | `/:familyId/budget` | Monthly budget, used, remaining, base rate |
| GET | `/:familyId/entitlements` | **Plan, status, limits and features — the client's source of truth** |
| GET | `/:familyId/members` | List active members |
| PATCH | `/:familyId/members/:userId/role` | Change role |
| POST | `/:familyId/members/:userId/approve` | Approve a pending join |
| POST · DELETE | `/:familyId/actors[/:actorId]` | Add / remove care dependent |
| POST | `/:familyId/actors/:actorId/avatar` | Upload dependent avatar |
| GET · POST | `/:familyId/invitations` | List / send email invitations |
| POST | `/join-request` · `/join-by-token` | Join by invitation or shareable link |
| GET · POST · DELETE | `/:familyId/invite-links[/:linkId]` | Manage shareable links |
| GET · POST | `/:familyId/deletion-requests[/:id/approve\|reject]` | Deletion consensus flow |

#### `/api/activities` — task engine
| Method | Path | Description |
|---|---|---|
| GET · POST | `/` | List / create templates and instances |
| DELETE | `/:id` | Delete template or un-schedule instance |
| POST | `/:id/approve` · `/schedule` · `/recurrence` | Approve, schedule, repeat |
| POST | `/:id/complete` · `/validate` · `/revert` | Completion and coin minting |
| POST | `/:id/bounty` · `/accept-bounty` | Offer and take over bounties |

#### `/api/admin` — platform admin (requires `platform_role = 'admin'`)
| Method | Path | Description |
|---|---|---|
| GET | `/status` | Admin self-check used to gate the console |
| GET | `/families` | Paged registry: search, heartbeat-bucket filter, counts, plan |
| GET | `/families/:familyId` | Registry detail (aggregates only) |
| POST | `/families/:familyId/notify-inactive` | Nudge caregivers via push; audited |
| GET | `/families/:familyId/billing` | Subscription, grants, billing-event metadata |
| POST · DELETE | `/families/:familyId/grants[/:grantId]` | Issue / revoke comps and trials |
| GET · POST | `/plans` · PATCH `/plans/:code` | Plan catalog CRUD |

#### Other
| Route | Description |
|---|---|
| `POST /api/billing/webhook` | RevenueCat events — shared-secret auth, no Firebase token |
| `GET /api/dashboard/:familyId` | Aggregate dashboard payload |
| `GET /api/stats/:familyId` | Analytics payload for the charts |
| `GET /api/marketplace/rewards/:familyId` | Active rewards and redemption history |
| `POST /api/marketplace/rewards` · `/rewards/:id/redeem` | Create reward (caregivers) · redeem atomically |
| `GET · POST · DELETE /api/absences` | Absence management |
| `GET · POST /api/personal-time` · `/quote` | Ask for personal time: price a window, escrow the sweetener, list requests (and sweep expired ones) |
| `POST /api/personal-time/:id/accept` · `/decline` · `DELETE /:id` | Accept (materializes the self ↔ coverage pair), decline, or withdraw |
| `POST /api/events` | Onboarding/telemetry events |
| `GET /health` | Unauthenticated healthcheck used by Docker |

---

## Part 3: Database schema

Defined in `backend/src/db/schema.sql`; incremental migrations live in `backend/scripts/migrate-*.sql` and are applied in order by `scripts/init-db.js` (idempotent — safe to re-run). Full column reference: `docs/database-schema.md`.

| Table | Purpose |
|---|---|
| `users` | Firebase-linked accounts. `firebase_uid`, `email`, `display_name`, `avatar_url`, `is_deleted`, **`platform_role`** (`user`/`admin`) |
| `families` | Core tenant. `name`, `monthly_coin_budget`, `created_by`, **`last_active_at`** (heartbeat) |
| `family_members` | User↔family join: `role` (caregiver/member), `alias`, `coin_balance`, `status` |
| `family_invitations` | Email invites, unique on `(family_id, email)` |
| `invite_links` | Shareable UUID tokens with optional expiry, max-uses and revocation |
| `actors` | Care dependents (child, elderly, pet) and person placeholders |
| `activities` | Templates (`is_template`) and scheduled instances; status, coin value, bounty, assignee. **`category`** (`care`/`self`) + **`type`** make it a base class with two subclasses |
| **`personal_time_requests`** | An ask, not a booking: window, sweetener, escrow, recurrence, expiry. Materializes a self ↔ coverage activity pair on accept |
| `coin_ledger` | Immutable transaction log of every coin movement |
| `marketplace_rewards` · `reward_redemptions` | Reward catalogue and redemption history |
| `absences` | Time-off periods used to avoid assigning unavailable members |
| `login_history` | Per-session login/logout with IP and user agent |
| `fcm_tokens` · `notification_preferences` | Push tokens (multi-device) and per-category opt-ins |
| `family_deletion_requests` · `family_deletion_approvals` | Unanimous deletion consensus |
| `onboarding_events` | Guided-tour / checklist instrumentation |
| **`plans`** | Subscription catalog: price, period, `limits` and `features` JSONB, default flag |
| **`family_plans`** | One subscription per family: plan, status, period end, platform, provider refs |
| **`billing_events`** | Raw provider webhook log; `event_id` UNIQUE gives idempotency |
| **`admin_grants`** | Admin-issued comps/trials, revoked by timestamp (never deleted) |
| **`admin_audit_log`** | One row per mutating admin action, written in the same transaction |

---

## Part 4: Platform admin & subscriptions

Design and implementation log: `docs/admin-family-management-plan.md`. Operational reference: `docs/backend.md` §18.

### The privacy boundary

A platform admin is **the landlord, not a housemate**. `users.platform_role` is a global axis deliberately separate from family roles, so being an admin grants *no* rights inside any family. Admin endpoints expose **registry aggregates and billing state only** — never member identities, activities, coins or rewards. `adminService` maps every row through an explicit field allowlist, and a CI test feeds it contaminated rows to prove nothing else leaks. Admins are promoted only from the server (`scripts/promote-admin.js`); there is no API path to the role, and every mutating admin call writes an `admin_audit_log` row.

### Family liveness

`families.last_active_at` is touched by middleware on **successful** family-scoped responses only (so unauthorized probes can't keep a family looking alive), throttled to one write per family per hour. The registry buckets it: **active** ≤ 30 days, **dormant** 30–90, **inactive** > 90. Cleanup is a process, not a button — an admin sends an audited inactivity notice, and `scripts/retention-sweep.js` later deletes only families that were noticed and stayed silent (dry-run by default).

### Entitlements

The backend is the single source of truth: clients read `/api/families/:id/entitlements`, never a store SDK. That is what makes one caregiver's iPhone purchase light up Pro for the Android grandparent. Effective entitlement merges three sources, **most generous wins**: the default plan, the subscription while in good standing (`trialing`/`active`/`in_grace`, plus `canceled` until the paid period ends), and unrevoked admin grants. Limits are `max_members`, `max_actors`, `max_active_rewards`; an absent key means unlimited. Lapsed subscriptions downgrade gracefully to the default plan — only `past_due` triggers the read-only gate (HTTP 402).

### Billing (RevenueCat)

Store rules require in-app purchases to go through StoreKit / Play Billing, so RevenueCat validates receipts and pushes lifecycle events to `POST /api/billing/webhook`, which normalizes them into `family_plans`. The Flutter app sets a `family_id` subscriber attribute before opening the paywall, because stores sell to a person while subscriptions belong to a family. Setup record and the remaining store checklist: `docs/RevenueCatSetup.md`.

---

## Part 5: Onboarding & starter tasks

Plan and log: `docs/family-setup-questionnaire-plan.md`.

The create-family flow is a four-step wizard — family details → caregivers → who you care for → starter tasks — with a progress bar, per-step validation and Back/Next.

The final step asks how the family wants to start. Choosing ready-made tasks shows eight **activity-area** chips (meals, cleaning, errands, kids' routines, homework, night care, pets, elder care), pre-checked from the dependents entered a step earlier, plus a preview listing every implied task with a checkbox. Choosing "start empty" creates no tasks at all.

The catalogue lives in the **client** (`lib/data/starter_packs.dart`) so titles resolve through `AppLocalizations` — a Spanish family is seeded in Spanish, which database rows written by the backend could never be. The chosen tasks travel in `POST /api/families` as `starterTasks` and are validated server-side (≤ 40 items, title length, known category, duration ≥ 15). An absent field falls back to the legacy English seeding; an empty array explicitly means "start empty". Starter coin values use the same budget rule the app suggests for user-created tasks.

---

## Part 6: Push notifications

Firebase Cloud Messaging, sent server-side by the Node Admin SDK.

**Token lifecycle:** the user enables notifications in Profile → permission requested → token saved via `POST /api/me/fcm-token`. On startup, `push_service.dart` silently refreshes and upserts the token (handling rotation). Tokens that fail a send as unregistered or invalid are pruned automatically.

**Events:**

| Event | Recipients | prefKey |
|---|---|---|
| New activity pending approval | Caregivers | `activity_assigned` |
| Activity scheduled for you | Assigned user | `activity_assigned` |
| Activity needs validation (past due) | Caregivers | `activity_assigned` |
| Activity completed | All family | `activity_completed` |
| Activity validated (coins awarded) | Assignee | `activity_validated` |
| Bounty offered | All family | `bounty_offered` |
| Member joined · deletion requested · inactivity notice | Caregivers | `family_events` |

Every notification carries `data.url`; tapping a background notification deep-links into the relevant view.

---

## Part 7: Activity lifecycle

1. **Template creation** — title, category, duration, coin value (suggested from the family budget).
2. **Approval** — a caregiver approves the template before it can be scheduled.
3. **Scheduling** — approved templates get a start time, optionally as a recurring series.
4. **Bounty (optional)** — a caregiver adds bonus coins; any member can take the task over.
5. **Completion** — the assignee marks it done → `pending_validation`.
6. **Validation** — a caregiver confirms → coins minted in `coin_ledger`, balance updated.
7. **Auto-complete** — `autoComplete.js` sweeps past-due approved tasks automatically.

```
pending → approved → pending_validation → completed
                   → rejected
```

---

## Part 8: Automated tests

### Backend unit tests — 208 tests

Node's built-in runner, mock DB clients, no database required.

```bash
cd backend && npm test
```

`activityService` · `familyService` · `personalTime` · `distributionService` · `absenceWindow` · `starterTasks` · `adminFoundation` · `adminRegistry` · `entitlements` · `billing` · `retention`. Coverage includes the personal-time request lifecycle and escrow, the presence-weighted monthly distribution, the activity lifecycle, budget and deletion consensus, admin authorization (403 matrix), the registry **leak-prevention** test, entitlement merging and suspension, webhook idempotency and event mapping, and the retention sweep.

### Flutter tests — 59 tests

```bash
cd fluterFront && flutter analyze && flutter test
```

UI kit, help sheet, coach marks and checklist · all four locales and ICU plurals · error localization · starter packs · personal-time types and repeats · absence windows · avatar content types · legal links · session rejection. Per-file detail in `docs/automatic-testing-E2E.md`.

### E2E — none yet

There is no automated end-to-end layer. The natural shape is Flutter's `integration_test/` against the Firebase Auth emulator; see `docs/automatic-testing-E2E.md`.

---

## Part 9: Local development

### Prerequisites
Node.js 20+ · PostgreSQL 16 · Flutter SDK · a Firebase project with Auth + FCM

### Environment variables

Copy `backend/.env.example` to `backend/.env`:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` · `PGSSL` | Postgres connection string and SSL toggle |
| `PORT` | API port (default 3000) |
| `FIREBASE_PROJECT_ID` | Firebase project |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to the service-account JSON (production; unset when using the Auth Emulator) |
| `ALLOWED_ORIGINS` | CORS whitelist |
| `RESEND_API_KEY` · `EMAIL_FROM` | Invitation email (omit the key to log to console) |
| `APP_URL` | Link base used in emails |
| `REVENUECAT_WEBHOOK_SECRET` | Must match the Authorization header on the RevenueCat webhook, or it returns 401 |

The Flutter app needs no env file: Firebase config is compiled in via `lib/firebase_options.dart`; the backend URL and RevenueCat keys are build-time defines.

### Running

```bash
# Database (once, or after pulling migrations)
cd backend && npm install && npm run db:init

# Backend, hot-reload on :3000
npm run dev

# App
cd ../fluterFront && flutter pub get
flutter run                                   # device / emulator
flutter run -d chrome --web-port 8080 \
  --dart-define=API_BASE=http://localhost:3000
```

Release builds pass the real keys:

```bash
flutter build appbundle --dart-define=API_BASE=https://mycarecoins.app \
                        --dart-define=RC_ANDROID_KEY=goog_XXXX
```

### With Docker

```bash
docker compose up --build -d
```

Starts Postgres 16, `db-init` (schema + migrations), the Node API, and the NGINX-served Flutter web build. Firebase credentials must be at `./firebase-credentials.json`.

### Operator scripts

```bash
node backend/scripts/promote-admin.js you@example.com   # grant/revoke platform admin (--demote)
node backend/scripts/retention-sweep.js                 # dry run; --apply to delete
```

### Testing subscriptions locally

RevenueCat delivers webhooks over the public internet, so a backend on `localhost` never receives them — a purchase will succeed on-device while the family stays on the free plan. Either test against the deployed server, or expose the local backend with a tunnel and point the webhook URL at it temporarily.

### Testing push locally

Enable notifications in Profile, then use Chrome DevTools → Application → Service Workers → **Push**:

```json
{"notification":{"title":"Test","body":"Hello"},"data":{"url":"/activities"}}
```

Mobile badges and home-screen behaviour need HTTPS — deploy or tunnel. On macOS, also allow Chrome notifications in System Settings.

---

## Part 10: Documentation index

| Document | Contents |
|---|---|
| `docs/PRODUCT.md` | Users, purpose, brand, design principles, feature set |
| `docs/DESIGN.md` | Design tokens and component rules |
| `docs/mobile-ux-proposal.md` | Mobile UX review and ranked proposal, D1–D4 decided (not yet implemented) |
| `docs/mobile-ux-phase1-brief.md` | Implementation brief for Phase 1 of that proposal, written for a coding agent |
| `docs/backend.md` | Backend technical reference (§18 covers admin, billing and retention) |
| `docs/flutter-frontend.md` | **Frontend technical reference** — structure, state, API client, l10n, push, purchases, build and run |
| `docs/database-schema.md` | Full column-level schema reference |
| `docs/admin-family-management-plan.md` | Platform admin, registry and subscription design + implementation log |
| `docs/RevenueCatSetup.md` | RevenueCat dashboard configuration record and store checklist |
| `docs/family-setup-questionnaire-plan.md` | Starter tasks and setup questionnaire design + log |
| `docs/i18n-plan.md` | Localization workflow and guardrails |
| `docs/onboarding-help-plan.md` | Guided tour, help sheet, activation checklist (layers 1–3 shipped) |
| `docs/personal-time-plan.md` | Personal time and coverage — the full design and per-phase implementation log |
| `docs/personal-time-handoff.md` | Superseded handoff for that work; kept for the class model and known issues |
| `docs/automatic-testing-E2E.md` | The test layers, per-file coverage, and the missing E2E layer |
| `docs/deployment-and-delivery.md` | **The runbook**: server deploy, iOS and Android delivery, and the Firebase / RevenueCat / Apple / Play configuration they depend on |
| `docs/running-instructions.txt` | Local run instructions |
