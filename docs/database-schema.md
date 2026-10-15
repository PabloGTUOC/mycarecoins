# Database Schema Reference

The schema uses PostgreSQL with the `uuid-ossp` extension loaded. Most tables use `BIGSERIAL` (numeric auto-increment) primary keys. Only three tables use UUIDs: `marketplace_rewards`, `reward_redemptions`, and `invite_links`.

---

## Table of Contents

1. [users](#1-users)
2. [families](#2-families)
3. [family_members](#3-family_members)
4. [family_invitations](#4-family_invitations)
5. [actors](#5-actors)
6. [activities](#6-activities)
7. [coin_ledger](#7-coin_ledger)
8. [login_history](#8-login_history)
9. [marketplace_rewards](#9-marketplace_rewards)
10. [reward_redemptions](#10-reward_redemptions)
11. [absences](#11-absences)
12. [invite_links](#12-invite_links)
13. [family_deletion_requests](#13-family_deletion_requests)
14. [family_deletion_approvals](#14-family_deletion_approvals)
15. [fcm_tokens](#15-fcm_tokens)
16. [notification_preferences](#16-notification_preferences)
17. [admin_audit_log](#17-admin_audit_log)
18. [plans](#18-plans)
19. [family_plans](#19-family_plans)
20. [billing_events](#20-billing_events)
21. [admin_grants](#21-admin_grants)
22. [personal_time_requests](#22-personal_time_requests)
23. [onboarding_events](#23-onboarding_events)
24. [admin_family_notices](#24-admin_family_notices)
25. [admin_rc_sync](#25-admin_rc_sync)
26. [Operator Console Views](#26-operator-console-views)
27. [The carecoins_admin Role](#27-the-carecoins_admin-role)

---

## 1. `users`

Core identity table. Each row represents one registered user, linked to Firebase Authentication.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal numeric identifier |
| `firebase_uid` | TEXT | UNIQUE, NOT NULL | UID issued by Firebase Auth; used for all token verification |
| `email` | TEXT | UNIQUE | User's email address (may be null if provider does not supply it) |
| `display_name` | TEXT | — | Human-readable name shown in the UI |
| `avatar_url` | TEXT | — | URL to the user's profile picture |
| `is_deleted` | BOOLEAN | NOT NULL, DEFAULT false | Soft-delete flag; deleted users are hidden but their data is preserved |
| `platform_role` | TEXT | NOT NULL, DEFAULT 'user', CHECK IN ('user','admin') | Global role, separate from family roles; set only via `scripts/promote-admin.js` |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Account creation timestamp |

**Logic notes:**
- Deletion is always soft (`is_deleted = true`), never a physical row removal, to preserve referential integrity across all other tables.
- `firebase_uid` is the join key between the Firebase token (JWT) and the internal user record.
- Child tables that reference `users(id)` (e.g. `family_members`, `actors`, `coin_ledger`) define their foreign keys with `ON DELETE CASCADE`. These constraints are never triggered by normal application flow — they exist as a safety net for direct database operations such as admin cleanup scripts or test teardown where a row might be hard-deleted outside the app.

---

## 2. `families`

Represents a family group. All shared data (activities, coins, rewards) belongs to a family.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `name` | TEXT | NOT NULL | Display name of the family |
| `monthly_coin_budget` | INTEGER | NOT NULL, DEFAULT 1000, CHECK > 0 | Total CareCoins distributed to caregivers each month |
| `last_coin_distribution_month` | VARCHAR(7) | — | Last month coins were distributed, in `YYYY-MM` format; used to prevent double distribution |
| `created_by` | BIGINT | NOT NULL, FK → users(id) | User who created the family |
| `last_active_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Heartbeat: touched (throttled, ≤1/h) by successful family-scoped requests; drives the admin registry's active/dormant/inactive buckets |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Logic notes:**
- `monthly_coin_budget` must be strictly positive (enforced by CHECK constraint).
- `last_coin_distribution_month` acts as an idempotency guard: the distribution job checks this value before issuing coins for the current month.

---

## 3. `family_members`

Junction table linking users to families with a role and a coin balance.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family this membership belongs to |
| `user_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | User who is a member |
| `role` | TEXT | NOT NULL, CHECK IN ('caregiver', 'member') | Role within the family |
| `alias` | TEXT | — | Optional nickname shown instead of `display_name` within this family |
| `coin_balance` | INTEGER | NOT NULL, DEFAULT 0 | Current CareCoins balance for this user in this family |
| `status` | TEXT | NOT NULL, DEFAULT 'active', CHECK IN ('active', 'pending', 'inactive') | Membership lifecycle state |
| `joined_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When the user joined |
| _(unique)_ | — | UNIQUE (family_id, user_id) | A user can only have one membership per family |

**Logic notes:**
- `role = 'caregiver'` grants elevated permissions (create activities, approve tasks, manage rewards).
- `role = 'member'` is the dependent being cared for; they receive coins but do not manage the family.
- `status = 'pending'` is set when an invitation is accepted but before a caregiver confirms the join.
- Coin balance is stored here (denormalized) for fast reads; the authoritative source of truth for coin changes is `coin_ledger`.

---

## 4. `family_invitations`

Email-based invitations sent by caregivers to recruit new family members.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family the invitation is for |
| `email` | TEXT | NOT NULL | Recipient's email address |
| `name` | TEXT | — | Optional display name for the invitee |
| `role` | TEXT | NOT NULL, DEFAULT 'caregiver' | Role that will be assigned on acceptance |
| `invited_by` | BIGINT | NOT NULL, FK → users(id) | Caregiver who sent the invitation |
| `status` | TEXT | NOT NULL, DEFAULT 'pending', CHECK IN ('pending', 'accepted', 'declined') | Current state of the invitation |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When the invitation was created |
| _(unique)_ | — | UNIQUE (family_id, email) | Only one active invitation per email per family |

**Logic notes:**
- The unique constraint on `(family_id, email)` prevents duplicate invitations; a caregiver must decline/revoke an existing one before re-inviting the same address.
- When a user accepts, the application creates a `family_members` row and sets this status to `'accepted'`.

---

## 5. `actors`

Represents individuals tracked within a family. An actor can be a registered user or an unregistered person (e.g. an elderly relative without an account).

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family this actor belongs to |
| `user_id` | BIGINT | FK → users(id) ON DELETE CASCADE | Linked user account (nullable for unregistered actors) |
| `actor_type` | TEXT | NOT NULL, DEFAULT 'person' | Type of actor |
| `name` | TEXT | — | Display name (used when `user_id` is null) |
| `care_time` | TEXT | CHECK IN ('full_time', 'part_time') | Care intensity; relevant for scheduling and workload metrics |
| `avatar_url` | TEXT | — | Profile picture URL |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| _(unique)_ | — | UNIQUE (family_id, user_id) | A registered user can only be one actor per family |

**Logic notes:**
- `user_id` is nullable to support actors who are not platform users (e.g. a patient being cared for).
- The unique constraint applies only when `user_id` is not null (PostgreSQL ignores NULLs in unique indexes).
- **Only actors with `actor_type = 'pet'` can be deleted.** Attempting to remove a child, elderly, or other actor type returns `403`. This is enforced at the service layer (`removeActor` in `memberService.js`).
- Removing a pet also decreases `families.monthly_coin_budget` by 720 (full-time) or 360 (part-time) — reversing the budget contribution that was added when the actor was created.

---

## 6. `activities`

The central entity of the application. A base class with two subclasses, distinguished by
`category`: **care** activities are work done for someone else and carry coins, **self**
activities are personal time and are always worth zero. `type` is the sub-type within the
subclass. Both columns are NOT NULL, which is load-bearing rather than tidiness — a CHECK
rejects only on *false*, so a nullable column would make an unmatched branch evaluate to
NULL and let a bad row through.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family this activity belongs to |
| `created_by` | BIGINT | NOT NULL, FK → users(id) | User who created the activity |
| `assigned_to` | BIGINT | FK → users(id) | User assigned to perform the task (nullable = unassigned) |
| `title` | TEXT | NOT NULL | Short description of the task |
| `category` | TEXT | NOT NULL, CHECK IN ('care', 'self') | The subclass: work for someone else, or personal time |
| `type` | TEXT | NOT NULL, compound CHECK with `category` | Sub-type: `care`/`household`/`coverage` when care, `sport`/`social`/`rest`/`appointment`/`other` when self |
| `starts_at` | TIMESTAMPTZ | — | Scheduled start time |
| `ends_at` | TIMESTAMPTZ | — | Scheduled end time |
| `duration_minutes` | INTEGER | NOT NULL, CHECK >= 15 | Expected duration; minimum 15 minutes |
| `coin_value` | INTEGER | NOT NULL, CHECK >= 0 | CareCoins awarded on completion |
| `status` | TEXT | NOT NULL, DEFAULT 'pending', CHECK IN ('pending', 'approved', 'rejected', 'completed', 'pending_validation') | Lifecycle state |
| `is_template` | BOOLEAN | NOT NULL, DEFAULT true | Whether this is a reusable template or a concrete instance |
| `is_recurrent` | BOOLEAN | NOT NULL, DEFAULT false | Whether the task repeats |
| `approved_by` | BIGINT | FK → users(id) | Caregiver who approved or rejected the activity |
| `approved_at` | TIMESTAMPTZ | — | Timestamp of the approval/rejection action |
| `bounty_amount` | INTEGER | NOT NULL, DEFAULT 0 | Additional coin bonus offered for completing this task |
| `bounty_offered_by` | BIGINT | FK → users(id) ON DELETE SET NULL | User who offered the bounty |
| `personal_time_request_id` | BIGINT | FK → personal_time_requests(id) ON DELETE SET NULL | The request this row was materialized from, if any |
| `counterpart_activity_id` | BIGINT | FK → activities(id) ON DELETE SET NULL | The row on the other side of the pair: self ↔ coverage |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| _(check)_ | — | CHECK (ends_at > starts_at) OR both NULL | End must be strictly after start if either is set |
| _(check)_ | — | compound CHECK on (`category`, `type`) | Each subclass may only carry its own types |
| _(check)_ | — | CHECK (category <> 'self' OR coin_value = 0) | Personal time never pays the person taking it |

**Status lifecycle:**
```
pending → approved → pending_validation → completed
        → rejected           ↑ revert ↓
                           approved
```

**Logic notes:**
- `duration_minutes >= 15` enforces a minimum meaningful task length.
- `coin_value >= 0` allows zero-coin tasks (chores done purely for contribution).
- The `ends_at > starts_at` check is relaxed when both are NULL (for templates with no scheduled time).
- `bounty_amount` is additive on top of `coin_value`; set to 0 when no bounty is active. On a coverage row it carries the requester's sweetener.
- `type = 'coverage'` is the one type exempt from the overlap check, in both directions: covering a dependent is supervision, not busy hands, so the coverer can still cook dinner inside that window. It is written **only** by the personal-time accept flow — the activity API validator accepts just `care` and `household`, so nobody can create one by hand.
- Self activities are excluded from every work aggregate and from presence weighting; otherwise the coverer would be paid twice.
- Two indexes are defined: `(assigned_to, starts_at, ends_at)` for schedule queries and `(family_id, status)` for dashboard filters.

---

## 7. `coin_ledger`

Immutable transaction log for all CareCoins movements. Every credit or debit is recorded here.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family context |
| `user_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | User whose balance changed |
| `activity_id` | BIGINT | FK → activities(id) ON DELETE SET NULL | Activity that triggered this entry (nullable for non-activity movements) |
| `amount` | INTEGER | NOT NULL | Coin delta; positive = credit, negative = debit |
| `reason` | TEXT | NOT NULL | Human-readable description of the transaction |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Transaction timestamp |

**Logic notes:**
- Rows are never updated or deleted (append-only ledger).
- `activity_id` is SET NULL on activity deletion so historical transactions are not lost.
- `family_members.coin_balance` is the denormalized running total; `coin_ledger` is the source of truth for auditing.

---

## 8. `login_history`

Session audit trail. Records every login and logout event per user.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `user_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | User this session belongs to |
| `login_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When the session started |
| `logout_at` | TIMESTAMPTZ | — | When the session ended (null = session still open) |
| `ip_address` | TEXT | — | Client IP address at login |
| `user_agent` | TEXT | — | HTTP User-Agent header at login |

**Logic notes:**
- A row is inserted on every successful authentication; `logout_at` is null until the user explicitly logs out.
- On logout, the application updates the most recent open session (`logout_at IS NULL`) for that user.
- Both `ip_address` and `user_agent` are captured only at login; they are not updated during the session.

---

## 9. `marketplace_rewards`

Rewards that family caregivers create and members can redeem with their CareCoins.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PRIMARY KEY, DEFAULT uuid_generate_v4() | UUID identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family that owns this reward |
| `creator_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | Caregiver who created it |
| `title` | TEXT | NOT NULL | Name of the reward |
| `description` | TEXT | — | Optional detailed description |
| `cost` | INTEGER | NOT NULL, CHECK > 0 | CareCoins required to redeem |
| `max_uses` | INTEGER | — | Maximum total redemptions allowed (null = unlimited) |
| `valid_from` | TIMESTAMPTZ | — | Start of the validity window (null = immediately available) |
| `valid_until` | TIMESTAMPTZ | — | End of the validity window (null = no expiry) |
| `status` | TEXT | NOT NULL, DEFAULT 'active', CHECK IN ('active', 'archived') | Whether the reward is currently available |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last modification timestamp |

**Logic notes:**
- `cost > 0` ensures a reward always has a non-zero price.
- `max_uses` is enforced at the application layer by counting rows in `reward_redemptions` before allowing a new redemption.
- Rewards are never hard-deleted; they are archived (`status = 'archived'`) to preserve redemption history.
- An index is defined on `(family_id, status)` for fast marketplace listing.

---

## 10. `reward_redemptions`

Records each time a user redeems a marketplace reward.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PRIMARY KEY, DEFAULT uuid_generate_v4() | UUID identifier |
| `reward_id` | UUID | NOT NULL, FK → marketplace_rewards(id) ON DELETE CASCADE | Reward that was redeemed |
| `user_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | User who redeemed it |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family context (denormalized for query efficiency) |
| `redeemed_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When the redemption occurred |

**Logic notes:**
- `family_id` is denormalized here (it could be derived via `reward_id → marketplace_rewards → family_id`) to avoid a join on every redemption query.
- The corresponding coin debit is written to `coin_ledger` as part of the same transaction.

---

## 11. `absences`

Records periods when a user is unavailable (holiday, sick leave, etc.), used to avoid scheduling conflicts.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family context |
| `user_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | User who is absent |
| `start_time` | TIMESTAMPTZ | NOT NULL | Start of the absence |
| `end_time` | TIMESTAMPTZ | NOT NULL | End of the absence |
| `title` | TEXT | NOT NULL | Label for the absence (e.g. "Vacation", "Doctor") |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| _(check)_ | — | CHECK (end_time > start_time) | End must be strictly after start |

**Logic notes:**
- The `CHECK (end_time > start_time)` constraint prevents zero-length or inverted absences at the database level.
- An index on `(family_id, start_time, end_time)` supports efficient overlap queries for scheduling.

---

## 12. `invite_links`

Shareable one-click invitation links that allow anyone with the URL to join a family.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PRIMARY KEY, DEFAULT uuid_generate_v4() | UUID used as the link token |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family being joined |
| `created_by` | BIGINT | NOT NULL, FK → users(id) | Caregiver who generated the link |
| `max_uses` | INTEGER | — | Maximum number of times the link can be used (null = unlimited) |
| `uses` | INTEGER | NOT NULL, DEFAULT 0 | How many times the link has been used so far |
| `expires_at` | TIMESTAMPTZ | — | Expiry timestamp (null = never expires) |
| `revoked` | BOOLEAN | NOT NULL, DEFAULT false | If true, the link is immediately invalidated |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |

**Logic notes:**
- The UUID primary key serves double duty as the unguessable token embedded in the invite URL.
- The application validates three conditions before accepting a link: `revoked = false`, `expires_at > NOW()` (if set), and `uses < max_uses` (if set).
- `uses` is incremented atomically on each successful join.
- An index on `family_id` supports listing all active links for a given family.

---

## 13. `family_deletion_requests`

Initiated when a caregiver requests that the entire family be deleted. Requires consent from all caregivers.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family targeted for deletion |
| `requested_by` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | Caregiver who initiated the request |
| `status` | TEXT | NOT NULL, DEFAULT 'pending', CHECK IN ('pending', 'approved', 'rejected') | Outcome of the multi-step approval process |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When the request was created |

**Logic notes:**
- A request moves to `'approved'` only after all caregivers have submitted an `'approved'` entry in `family_deletion_approvals`.
- If any caregiver rejects, the request moves to `'rejected'` and no deletion occurs.

---

## 14. `family_deletion_approvals`

Tracks each caregiver's individual vote on a family deletion request.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `request_id` | BIGINT | NOT NULL, FK → family_deletion_requests(id) ON DELETE CASCADE | The deletion request being voted on |
| `caregiver_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | Caregiver casting the vote |
| `status` | TEXT | NOT NULL, DEFAULT 'pending', CHECK IN ('pending', 'approved', 'rejected') | This caregiver's vote |
| `responded_at` | TIMESTAMPTZ | — | When the vote was cast (null = not yet voted) |
| _(unique)_ | — | UNIQUE (request_id, caregiver_id) | Each caregiver can only vote once per request |

**Logic notes:**
- One row is created per caregiver (with `status = 'pending'`) when a deletion request is opened.
- The unique constraint on `(request_id, caregiver_id)` prevents duplicate votes.
- After every vote update, the application re-evaluates the parent `family_deletion_requests.status`.

---

## 15. `fcm_tokens`

Stores Firebase Cloud Messaging device tokens for push notification delivery.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `user_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | User this token belongs to |
| `token` | TEXT | NOT NULL, UNIQUE | FCM registration token for a specific device/browser |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When the token was registered |

**Logic notes:**
- A user can have multiple tokens (one per device/browser).
- Tokens are upserted via `POST /api/me/fcm-token` — if the same token is re-registered it is a no-op.
- After each FCM send, tokens reported as invalid or unregistered by Firebase are pruned automatically.
- An index on `user_id` supports fast lookup of all tokens for a given user.

---

## 16. `notification_preferences`

Per-user opt-in/opt-out settings for each push notification category.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `user_id` | BIGINT | PRIMARY KEY, FK → users(id) ON DELETE CASCADE | User these preferences belong to |
| `activity_assigned` | BOOLEAN | NOT NULL, DEFAULT true | Receive notifications when an activity is assigned or scheduled |
| `activity_validated` | BOOLEAN | NOT NULL, DEFAULT true | Receive notifications when a completed activity is validated |
| `activity_completed` | BOOLEAN | NOT NULL, DEFAULT true | Receive notifications when any family member completes an activity |
| `bounty_offered` | BOOLEAN | NOT NULL, DEFAULT true | Receive notifications when a bounty is offered on an activity |
| `family_events` | BOOLEAN | NOT NULL, DEFAULT true | Receive notifications for family-level events (member joined, deletion requested) |

**Logic notes:**
- One row per user (primary key = `user_id`). The row is created/replaced atomically via `PUT /api/me/notification-preferences`.
- Before sending a push notification, `notify.js` LEFT JOINs this table and skips users where the relevant column is `false`.
- All categories default to `true`, so users who have never visited the preferences screen receive all notifications.

---

## 17. `admin_audit_log`

One row per mutating platform-admin action, written in the same transaction as the mutation (see `docs/admin-family-management-plan.md`).

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `admin_id` | BIGINT | NOT NULL, FK → users(id) | Admin who performed the action |
| `action` | TEXT | NOT NULL | Dotted action name (`plan.create`, `grant.revoke`, `family.notify_inactive`, `family.retention_delete`, …) |
| `target_type` | TEXT | NOT NULL | `family`, `plan`, or `none` |
| `target_id` | TEXT | — | Target identifier as text |
| `payload` | JSONB | — | Action-specific detail |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When it happened |

---

## 18. `plans`

Subscription plan catalog, managed via `/api/admin/plans`.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `code` | TEXT | PRIMARY KEY | Stable identifier (`free`, `plus`, …) |
| `name` | TEXT | NOT NULL | Display name |
| `price_cents` | INTEGER | NOT NULL, DEFAULT 0, CHECK >= 0 | Price per period |
| `currency` | TEXT | NOT NULL, DEFAULT 'EUR' | ISO currency |
| `billing_period` | TEXT | NOT NULL, DEFAULT 'monthly', CHECK IN ('monthly','yearly') | Billing cadence |
| `limits` | JSONB | NOT NULL, DEFAULT '{}' | Limit keys (`max_members`, `max_actors`, `max_active_rewards`); an absent key means unlimited |
| `features` | JSONB | NOT NULL, DEFAULT '{}' | Feature flags granted by the plan |
| `is_default` | BOOLEAN | NOT NULL, DEFAULT false | The plan every family starts on (exactly one in practice) |
| `active` | BOOLEAN | NOT NULL, DEFAULT true | Inactive plans cannot be granted |

---

## 19. `family_plans`

One subscription record per family; the single source of truth clients read entitlements from (via the backend, never a store SDK).

| Column | Type | Constraints | Description |
|---|---|---|---|
| `family_id` | BIGINT | PRIMARY KEY, FK → families(id) ON DELETE CASCADE | One row per family |
| `plan_code` | TEXT | NOT NULL, FK → plans(code) | Current plan |
| `status` | TEXT | NOT NULL, DEFAULT 'active', CHECK IN ('trialing','active','in_grace','past_due','paused','canceled','expired') | Subscription lifecycle state |
| `current_period_end` | TIMESTAMPTZ | — | End of the paid period |
| `platform` | TEXT | — | `app_store` / `play` (future: `stripe`) |
| `provider` | TEXT | — | `system`, `revenuecat`, … |
| `provider_subscription_id` | TEXT | — | Provider-side reference for support lookups |
| `billing_owner_user_id` | BIGINT | FK → users(id) | Whose store account pays |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last state change |

**Logic notes:**
- `trialing`/`active`/`in_grace` confer plan benefits; `canceled`/`expired`/`paused` downgrade gracefully to the default plan; only `past_due` puts the family in read-only mode (`assertFamilyWritable`, HTTP 402).

---

## 20. `billing_events`

Raw payment-provider webhook log; gives idempotency (`event_id` UNIQUE) and a debugging trail. Admin endpoints expose only metadata, never `payload`.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `provider` | TEXT | NOT NULL | Event source |
| `event_id` | TEXT | UNIQUE | Provider's event id; dedupes replays |
| `event_type` | TEXT | NOT NULL | Provider event name (`RENEWAL`, `CANCELLATION`, …) |
| `family_id` | BIGINT | FK → families(id) ON DELETE SET NULL | Attributed family |
| `payload` | JSONB | NOT NULL | Raw event body |
| `processed` | BOOLEAN | NOT NULL, DEFAULT false | Whether the event was applied to `family_plans` |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Receipt time |

---

## 21. `admin_grants`

Comps/trials issued by platform admins — deliberately separate from `family_plans` so store truth and admin truth never overwrite each other. Effective entitlement is the most generous of both.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Beneficiary family |
| `plan_code` | TEXT | NOT NULL, FK → plans(code) | Granted plan |
| `granted_by` | BIGINT | NOT NULL, FK → users(id) | Admin who granted it |
| `reason` | TEXT | — | Free-text justification |
| `expires_at` | TIMESTAMPTZ | — | Optional expiry; NULL = open-ended |
| `revoked_at` | TIMESTAMPTZ | — | Revocation timestamp (never hard-deleted) |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Grant time |

---

## 22. `personal_time_requests`

An ask, not a booking. Personal time always carries a coverage offer to another caretaker
and is only real once they accept — you cannot decline your partner's work trip, but you can
decline their gym session. Nothing is scheduled while a request is pending; on acceptance two
ordinary `activities` rows are materialized (the requester's self activity, worth nothing,
and the accepter's coverage shift, worth the family base rate plus any sweetener), so every
existing query over `activities` keeps working untouched.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Family the request belongs to |
| `requester_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | Who wants the time |
| `requested_of` | BIGINT | FK → users(id) ON DELETE CASCADE | Who is being asked; **NULL means "ask anyone"** — any active caregiver may accept, first one wins |
| `parent_request_id` | BIGINT | FK → personal_time_requests(id) ON DELETE CASCADE | Reserved for per-instance renegotiation of a series; not yet written |
| `title` | TEXT | NOT NULL | What the time is for |
| `type` | TEXT | NOT NULL, CHECK IN ('sport', 'social', 'rest', 'appointment', 'other') | The self sub-type, mirroring `activities.type` |
| `description` | TEXT | — | Optional note for whoever has to answer |
| `starts_at` · `ends_at` | TIMESTAMPTZ | NOT NULL | The window asked for |
| `coverage_needed` | BOOLEAN | NOT NULL, DEFAULT true | False = the dependent needs nobody then (gym while the kid is at daycare). The partner is still told, but there is nothing to accept and no coins move |
| `baseline_coins` | INTEGER | NOT NULL, DEFAULT 0, CHECK >= 0 | What covering the window is worth at the family base rate |
| `sweetener_coins` | INTEGER | NOT NULL, DEFAULT 0, CHECK >= 0 | Extra offered from the requester's own wallet, **per occurrence** |
| `escrowed_coins` | INTEGER | NOT NULL, DEFAULT 0, CHECK >= 0 | What actually left the wallet: `sweetener_coins × occurrences` |
| `recurrence` | TEXT | CHECK IN ('daily', 'weekdays', 'weekly') | NULL = a one-off |
| `recurrence_until` | DATE | — | Last day a repeat may fall on, inclusive |
| `status` | TEXT | NOT NULL, DEFAULT 'pending', CHECK IN ('pending', 'accepted', 'declined', 'expired', 'cancelled') | Lifecycle state |
| `responded_by` | BIGINT | FK → users(id) | Who answered; NULL on a request nobody had to answer |
| `responded_at` | TIMESTAMPTZ | — | When it was answered |
| `expires_at` | TIMESTAMPTZ | NOT NULL | `min(asked + 48 h, starts_at)` |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Creation timestamp |
| _(check)_ | — | CHECK (ends_at > starts_at) | |
| _(check)_ | — | CHECK (ends_at - starts_at <= INTERVAL '24 hours') | Beyond a day it is an absence, not personal time |

**Logic notes:**
- **The sweetener is priced per occurrence and escrowed up front.** Ten Fridays at 5 cc is ten
  favours asked, so the whole 50 leaves the wallet at creation. `escrowed_coins` records what
  actually left, separately from the per-occurrence `sweetener_coins`, so a refund never has to
  recompute an occurrence list to know what to give back — a refund that recomputes is a refund
  that can drift. Refunds write the column down as they pay, which is what makes the expiry
  sweep idempotent.
- Accepting a series materializes a pair per occurrence and **skips** any the accepter is away
  for or the requester has since filled, refunding `sweetener_coins × skipped`. A series nobody
  can make at all is refused rather than accepted empty, so it stays pending for someone else.
- Expiry runs from `listRequests`, not from the activity sweep. If nobody opens the app nothing
  expires — acceptable, because accepting an expired request is already refused, so the sweep is
  about the money rather than about correctness.
- Two indexes: `(family_id, status, starts_at)` for the calendars, `(requested_of, status)` for
  "what am I being asked".
- **Declines are never counted anywhere** — not in stats, not on the dashboard. Declining has to
  stay free and invisible, or the sweetener stops being an offer and becomes social pressure.

---

## 23. `onboarding_events`

Instrumentation for the guided tour and the activation checklist — which steps a user
reached, and where they stopped. Written by `POST /api/events`; see
`docs/family-setup-questionnaire-plan.md` and `docs/onboarding-help-plan.md`.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `user_id` | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | Who the event belongs to |
| `event` | TEXT | NOT NULL | Event name, e.g. a tour step or checklist item |
| `detail` | JSONB | — | Free-form payload for the event |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When it happened |

**Logic notes:**
- Deliberately append-only and user-scoped, not family-scoped: it records what a *person*
  did during onboarding, and cascades away with the account.
- No index beyond the primary key — the table is written far more often than it is read.

---

## 24. `admin_family_notices`

Queue table for family notices requested by the operator console (see `docs/management-platform-plan.md` §2.3). The console's database role (`carecoins_admin`) cannot see who belongs to a family, so it only queues requests; the public backend sends the push (`src/services/noticeOutbox.js`).

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | BIGSERIAL | PRIMARY KEY | Internal identifier |
| `family_id` | BIGINT | NOT NULL, FK → families(id) ON DELETE CASCADE | Target family |
| `kind` | TEXT | NOT NULL, CHECK IN ('inactive') | Notice type |
| `requested_by` | BIGINT | NOT NULL, FK → users(id) | Admin operator who requested the notice |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Queued timestamp |
| `sent_at` | TIMESTAMPTZ | — | Timestamp when sent (null = unsent) |

**Logic notes:**
- `idx_admin_family_notices_unsent` indexes `(id) WHERE sent_at IS NULL` for fast outbox polling.
- The public backend worker claims batches using `FOR UPDATE SKIP LOCKED` and stamps `sent_at = NOW()` atomically before dispatching pushes.

---

## 25. `admin_rc_sync`

Tracks synchronization of free-plan grants into RevenueCat (plan §4). One row per grant; the operator console's sync loop moves it from pending to synced or failed.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `grant_id` | BIGINT | PRIMARY KEY, FK → admin_grants(id) ON DELETE CASCADE | Associated grant |
| `rc_customer_id` | TEXT | NOT NULL | Synthetic RevenueCat customer id (`family_<id>`) |
| `action` | TEXT | NOT NULL, CHECK IN ('grant', 'revoke') | Desired mirror action |
| `status` | TEXT | NOT NULL, CHECK IN ('pending', 'synced', 'failed') | Sync status |
| `attempts` | INTEGER | NOT NULL, DEFAULT 0 | Number of sync attempts |
| `last_error` | TEXT | — | Error message from most recent failed attempt |
| `synced_at` | TIMESTAMPTZ | — | Successful sync timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last update timestamp |

---

## 26. Operator Console Views

Two `security_barrier` views provide the operator console API with necessary registry and authorization data without granting it direct access to underlying content tables (`users`, `family_members`, `actors`).

### `admin_family_registry`

Runs with owner rights over `families` LEFT JOIN `family_plans`, using subqueries for active/pending member counts and actor count.

Columns:
- `id`: family id
- `name`: family name
- `created_at`: creation timestamp
- `last_active_at`: heartbeat timestamp (used for active/dormant/inactive status calculation)
- `plan_code`: active plan code
- `subscription_status`: subscription status
- `member_count`: count of active family members
- `pending_member_count`: count of pending family members
- `actor_count`: count of non-user actors (objects of care)

### `admin_operators`

Filters `users` to active platform administrators (`platform_role = 'admin' AND is_deleted = false`). Used by `requireOperator` (`src/admin/operator.js`) to verify callers without granting `carecoins_admin` read access to the general `users` table and without upserting users.

Columns:
- `id`: internal user id
- `firebase_uid`: Firebase Authentication UID

---

## 27. The `carecoins_admin` Role

The Postgres security role used by the operator console API (`admin-api` container). Created and maintained by `backend/scripts/admin-role.js` via `backend/scripts/init-db.js`.

- **Password configuration:** set via `ADMIN_DB_PASSWORD` (read by `db-init` to alter role password and by `admin-api` via `PGPASSWORD` through `src/admin/env.js`).
- **Privacy boundary:** completely prohibited from accessing any of the 18 content tables defined in `FORBIDDEN_TABLES`:
  `users`, `families`, `family_members`, `actors`, `activities`, `coin_ledger`, `marketplace_rewards`, `reward_redemptions`, `absences`, `personal_time_requests`, `family_invitations`, `invite_links`, `fcm_tokens`, `notification_preferences`, `login_history`, `onboarding_events`, `family_deletion_requests`, `family_deletion_approvals`.
- **Allowed capabilities:**
  - `USAGE` on schema `public`
  - `SELECT` on views `admin_family_registry` and `admin_operators`
  - `SELECT` on `plans`, `family_plans`, `admin_grants`, `admin_audit_log`, `admin_rc_sync`, `admin_family_notices`
  - `SELECT (id, provider, event_id, event_type, family_id, processed, created_at)` on `billing_events` (column-restricted; raw `payload` is blocked)
  - `INSERT, UPDATE` on `plans` and `admin_rc_sync`
  - `INSERT, UPDATE (revoked_at)` on `admin_grants`
  - `INSERT` on `admin_audit_log` and `admin_family_notices`
  - `USAGE` on sequences `admin_grants_id_seq`, `admin_audit_log_id_seq`, `admin_family_notices_id_seq`
- **Verification:** verified against a real Postgres 16 instance by `backend/scripts/check-admin-role.js`.

---

## Indexes Summary

| Index | Table | Columns | Purpose |
|---|---|---|---|
| `idx_activities_assignee_period` | `activities` | `(assigned_to, starts_at, ends_at)` | Schedule queries for a specific assignee |
| `idx_activities_family_status` | `activities` | `(family_id, status)` | Dashboard and kanban filters |
| `idx_marketplace_family_status` | `marketplace_rewards` | `(family_id, status)` | Active reward listing per family |
| `idx_absences_family_period` | `absences` | `(family_id, start_time, end_time)` | Overlap detection for scheduling |
| `idx_invite_links_family` | `invite_links` | `(family_id)` | List all links for a family |
| `idx_fcm_tokens_user_id` | `fcm_tokens` | `(user_id)` | Fetch all device tokens for a user before sending push notifications |
| `idx_families_last_active` | `families` | `(last_active_at)` | Admin registry ordering and status-bucket filters |
| `idx_admin_audit_log_admin_time` | `admin_audit_log` | `(admin_id, created_at)` | Audit trail lookups per admin |
| `idx_billing_events_family` | `billing_events` | `(family_id, created_at)` | Billing history per family |
| `idx_admin_grants_family` | `admin_grants` | `(family_id)` | Grant lookups during entitlement merges |
| `idx_admin_family_notices_unsent` | `admin_family_notices` | `(id) WHERE sent_at IS NULL` | Fast polling of unsent notice queue |

