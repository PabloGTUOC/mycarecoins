# Activity Subclasses, Personal Time & Coverage — Plan

> **Status: all seven phases implemented** (see §9, an **As built** note per phase). The
> design below is revision 3, kept as the reasoning behind what was built.
> Companion docs: `docs/PRODUCT.md`, `docs/backend.md`, `docs/database-schema.md`.

**The scenario:** "I want to go to the gym Friday 18:00–19:30. I double-tap that hour on
the Daily view, name it, set a duration and a short note, optionally sweeten it from my own
coins. The other caretaker gets a counter care activity for that window, worth the base
rate. They can decline."

### Changes in revision 3

1. **Correction — revisions 1 and 2 missed the monthly GDP distribution**
   (`dashboard.js:17–95`). It changes the economics fundamentally: explicit activities are
   **zero-sum** against an unclaimed residual, not newly minted money. Every inflation
   concern in the earlier revisions is void (§2).
2. **Absences will pay the present caretaker** — via presence-weighted residual, not by
   generating activities. This is the correction Pablo raised; the code does not do it today
   (§3.1, §5.2).
3. **Activities become a base class with two subclasses, `care` and `self`** (§4), so a self
   activity and the counter care activity it creates can occupy the same window.
4. **The 24 h boundary cliff from revision 2 is resolved** and inverted — dodging via a 24 h
   absence now costs ~5× more than asking honestly (§5.3).

---

## 1. Current state

### 1.1 Three time primitives

| Primitive | Meaning | Who it moves | Coins | Consent |
|---|---|---|---|---|
| **Activity** (`care` \| `household`) | Value-producing work | Only yourself | `coin_value` to the doer on completion | None |
| **Bounty** | Bonus to shed a shift you own | Reassigns an existing shift | Escrows *your* coins, first-come grab | None |
| **Absence** | You are unavailable | Nobody | None | None |

**Activities are always self-assigned.** `scheduleActivity` inserts `assigned_to = userId`;
the only later mutation of `assigned_to` in the whole backend is `acceptBounty`, where the
accepter assigns it to *themselves*. No role can put work on another person's calendar.

**Absences touch no coin path.** `absences` appears in exactly two backend files —
`app.js` (mount) and `routes/absences.js`. It is absent from `dashboard.js` and `stats.js`.
There is no minimum duration; the dialog defaults to 09:00–17:00 on one day.

### 1.2 The economy actually has two layers

This is what revisions 1 and 2 got wrong. Coins reach a caregiver two ways:

**Layer 1 — explicit activities.** `coin_value = max(1, round(baseRatePerHour × minutes/60))`,
credited to the doer on completion, or automatically by `runAutoCompleteSweep` once
`ends_at` passes.

**Layer 2 — the monthly GDP residual** (`dashboard.js:17–95`, run lazily on the first
dashboard load of a new month, sweeping every elapsed month):

```
totalGdp  = Σ over dependents:  full_time → daysInMonth × 24,  part_time → half
explicit  = Σ coin_value of activities completed that month
unclaimed = max(0, totalGdp − explicit)
share     = floor(unclaimed / activeCaregivers)      ← split EVENLY, credited to each
```

The dependent generates one coin per hour of existence. Logged work claims part of it; the
rest is divided equally among caregivers as `monthly_distribution`.

### 1.3 The consequence everyone should understand

Because `unclaimed = totalGdp − explicit`, **logging an activity does not create money — it
moves money from the evenly-split residual to the person who did the work.**

> Two caregivers, one full-time dependent, 30-day month. `totalGdp` 720, explicit 200,
> unclaimed 520 → 260 each. Add a 2 cc activity: explicit 202, unclaimed 518 → 259 each,
> and the doer also earns 2 → **261 vs 259**. Total unchanged. Zero-sum.

The system only mints new money once `explicit` exceeds `totalGdp`, where `unclaimed`
clamps at zero. That — not `monthly_coin_budget` — is the real ceiling.

**Minor inconsistency found:** `monthly_coin_budget` is fixed at 720/360 per dependent at
family creation and drives `baseRatePerHour` and task pricing, while the distribution uses
the actual `daysInMonth × 24`. They disagree by 48 coins in February and 24 in July.

---

## 2. What this does to the earlier revisions

| Revision 1–2 claim | Status |
|---|---|
| "Coverage minted from the budget inflates the money supply" | **Void.** Explicit activities are zero-sum against the residual (§1.3). |
| "Cap personal time via `plans.limits`, make the budget a hard block" | **Dropped.** No cap needed. |
| "A 90-min gym slot costs the household 2 cc" | **Refined.** It costs the *requester* ~1 cc of residual share and gives the coverer ~1, plus the 2 cc credit. |
| "Absences are economically inert" | **True today, and wrong as a design.** Fixed in §3.1. |
| "The 24 h boundary is a payment cliff" | **Resolved** by §3.1 — see §5.3. |

---

## 3. The two settlement paths

The 24 h duration partition from revision 2 turns out to have a real economic meaning, not
just a duration rule. Each side gets the settlement mechanism it suits.

### 3.1 Absence (≥ 24 h) — settled at month end, no consent

**The coins for the hours you are away go to the caretaker who was present.**

Today `share = floor(unclaimed / caretakers.length)` ignores absences entirely. It becomes
presence-weighted:

```
presentHours_i = hoursInMonth − (that caregiver's absent hours falling inside the month)
share_i        = floor(unclaimed × presentHours_i / Σ presentHours)
```

Conserves the total, needs no new coin flow, and degrades correctly: one caregiver → gets
everything; nobody absent → today's even split exactly.

No consent is asked, because you cannot decline your partner's business trip. It is
automatic and retrospective, which is right for coarse, whole-day unavailability.

> 2 caregivers, unclaimed 520, one away 3 days (72 h): present 648 vs 720 → **246 vs 273**
> instead of 260/260. The trip costs the traveller 14 coins.

**Edge cases:** `Σ presentHours = 0` → fall back to the even split. A caregiver who joined
mid-month should count present hours only from `joined_at`. Floor each share and leave the
rounding remainder unspent, as the code does today.

### 3.2 Self activity (< 24 h) — settled immediately, requires consent

Month-end accounting is useless for a 90-minute gym slot: it is invisible, retrospective and
unrefusable. Short discretionary time gets the opposite treatment — an **explicit counter
care activity**, created immediately, visible on both calendars, and **refusable**.

**Do not apply presence weighting to self-activity hours.** They are already settled by the
explicit counter activity; counting them twice would pay the coverer for the same hour on
both layers. Clean division of labour:

| | Absence ≥ 24 h | Self activity < 24 h |
|---|---|---|
| Settled | Month end, automatically | Immediately, on acceptance |
| Mechanism | Presence-weighted residual | Explicit counter care activity |
| Refusable | No | **Yes** |
| Sweetener | No | Yes, from the requester's wallet |

---

## 4. The activity class model

Today `category` conflates two different questions — *is this a contribution at all?* and
*which kind of contribution?* Splitting them is what lets a self activity and its counter
care activity coexist in one window.

```
activity  (base: title, description, window, duration, assignee, status)
│
├── category = 'care'   contribution to the family
│                       type ∈ {care, household, coverage};  coin_value > 0
│                       coverage is written only by accepting a request, and is
│                       the one type allowed to overlap another activity
│
└── category = 'self'   personal time
                        type ∈ {sport, social, rest, appointment, other}
                        coin_value = 0;  pays nobody
                        always paired with a counter care activity
```

`category` is the subclass; `type` is the sub-type within it. Both are NOT NULL — there is
no "no type" state, and the picker asks for a type when personal time is created.
`category` defaults to `'care'`, so every existing row is correct with no backfill.

Keeping both columns NOT NULL is load-bearing, not tidiness: a CHECK rejects only on
*false*, so a nullable column makes an unmatched branch evaluate to NULL and the bad row
slips through.

### 4.1 Overlap rules become subclass-aware

`scheduleActivity` currently rejects any overlap for the same assignee. That rule has to
become a matrix, or the feature breaks in two places:

| Existing (same person) ↓ / New → | care | coverage | self |
|---|---|---|---|
| **care** | blocked (today's rule) | **allowed** | blocked |
| **coverage** | **allowed** | blocked | blocked |
| **self** | blocked | blocked | blocked |

Different people never conflict, so my self activity and my partner's counter care activity
coexist by construction.

**The `care` × `coverage` cell is the one that matters.** Coverage is supervisory: the
coverer will still cook dinner and run bath time inside that window. Under the old rule,
accepting coverage would have locked them out of scheduling their own evening tasks. Tasks
nested inside coverage pay normally on top — the coverage baseline pays for *being tied to
the house*, the task pays for *the labour*, and both draw down the same residual, so it
stays zero-sum.

Coverage is identified by `type = 'coverage'`, not by inference: the overlap checks in
`scheduleActivity` and `createRecurrence` carry `AND type <> 'coverage'`.
`personal_time_request_id` still exists, but for linking a shift back to the request that
created it — declines and refunds — not for saying what kind of row it is.

### 4.2 What each subclass does to the ledger

| | Owner | Coin value | Counts toward `explicit` | Presence weighting |
|---|---|---|---|---|
| care | doer | base rate × hours | yes | — |
| coverage | coverer | base rate × hours + sweetener | yes (baseline only) | — |
| self | requester | 0 | no | excluded (§3.2) |

The sweetener rides on the coverage row's existing `bounty_amount`, so
`runAutoCompleteSweep` pays it out with no new payout code, and it must be excluded from
`explicit` — it is the requester's own coins, not a claim on the residual.

---

## 5. Decisions

### 5.1 Duration partition

| | Self activity | Absence |
|---|---|---|
| Duration | 15 min – 24 h | **≥ 24 h** |
| Purpose | Discretionary personal time | Work travel, urgent family matters |
| Coverage | Counter activity, refusable | None — settled by presence weighting |

**Migration caveat:** live databases hold absences shorter than 24 h. A
`CHECK (end_time - start_time >= INTERVAL '24 hours')` will not apply. Enforce in
`validateBody` and add the constraint `NOT VALID` so it binds new rows only.

**UI consequence:** the absence dialog's two datetime pickers and 09:00→17:00 default become
invalid — it becomes a date-range picker defaulting to today → tomorrow.

### 5.2 The cliff is resolved

With §3.1 in place, declaring a 24 h absence to dodge a negotiation now costs more than
asking:

| Path | Requester's residual | Their net |
|---|---|---|
| Ask honestly (90 min gym, 2 cc baseline) | 260 → 259 | **−1 cc** |
| Dodge with a 24 h absence | 260 → 255 | **−5 cc** |

The dodge is 5× more expensive *and* burns a whole day of calendar. Revision 2 accepted this
cliff reluctantly; it no longer exists.

### 5.3 The 24 h maximum — sound, with a rendering caveat

The Daily grid is `kStartHour = 6`, `kTotalHours = 18` — 06:00 to midnight, one day. Blocks
longer than ~12 h or crossing midnight cannot be drawn. Absences already render as chips
outside the hour grid; long self activities reuse that. The picker offers 30 min – 12 h; the
API enforces the 24 h ceiling.

### 5.4 Remaining choices

- **Who is asked** — two caregivers: the other, automatically. Three or more: a picker, plus
  an "ask anyone" mode where the first to accept wins.
- **"No coverage needed"** — gym at 10:00 with the kid at daycare needs nobody. Default to
  requesting coverage, with a toggle for none; still notifies the partner (visible,
  falsifiable), no acceptance, no coins.
- **Series** — request the series, accept the series. `parent_request_id` exists from day one
  so per-instance renegotiation can be added later.
- **Expiry** — `min(request + 48 h, starts_at)`; refunds the sweetener; swept from
  `runAutoCompleteSweep`.

---

## 6. Data model

```sql
-- 1. The subclass, and the sub-type within it. What `category` used to hold is
--    now `type`; DEFAULT 'care' makes every existing row correct with no backfill.
ALTER TABLE activities RENAME COLUMN category TO type;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'care';
ALTER TABLE activities ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE activities ADD CONSTRAINT activities_category_type_check CHECK (
  (category = 'care' AND type IN ('care', 'household')) OR
  (category = 'self' AND coin_value = 0
                     AND type IN ('sport', 'social', 'rest', 'appointment', 'other'))
);

-- 3. Absence floor. NOT VALID: existing short absences are grandfathered (§5.1).
ALTER TABLE absences ADD CONSTRAINT absences_min_duration
  CHECK (end_time - start_time >= INTERVAL '24 hours') NOT VALID;

-- 4. The negotiation. Mirrors family_deletion_requests in spirit.
CREATE TABLE personal_time_requests (
  id                BIGSERIAL PRIMARY KEY,
  family_id         BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  requester_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requested_of      BIGINT REFERENCES users(id) ON DELETE CASCADE,   -- NULL = ask anyone
  parent_request_id BIGINT REFERENCES personal_time_requests(id) ON DELETE CASCADE,
  title             TEXT NOT NULL,
  description       TEXT,
  starts_at         TIMESTAMPTZ NOT NULL,
  ends_at           TIMESTAMPTZ NOT NULL,
  coverage_needed   BOOLEAN NOT NULL DEFAULT true,
  baseline_coins    INTEGER NOT NULL CHECK (baseline_coins >= 0),
  sweetener_coins   INTEGER NOT NULL DEFAULT 0 CHECK (sweetener_coins >= 0),
  recurrence        TEXT CHECK (recurrence IN ('daily','weekdays','weekly')),
  recurrence_until  DATE,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','accepted','declined','expired','cancelled')),
  responded_by      BIGINT REFERENCES users(id),
  responded_at      TIMESTAMPTZ,
  expires_at        TIMESTAMPTZ NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (ends_at > starts_at),
  CHECK (ends_at - starts_at <= INTERVAL '24 hours')
);

CREATE INDEX ON personal_time_requests (family_id, status, starts_at);
CREATE INDEX ON personal_time_requests (requested_of, status);

-- 5. Link the materialized pair to its request, and to each other.
ALTER TABLE activities ADD COLUMN IF NOT EXISTS personal_time_request_id BIGINT
  REFERENCES personal_time_requests(id) ON DELETE SET NULL;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS counterpart_activity_id BIGINT
  REFERENCES activities(id) ON DELETE SET NULL;

-- 6. Notification preference key.
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS coverage_requests BOOLEAN NOT NULL DEFAULT true;
```

New `coin_ledger` reasons: `coverage_sweetener_escrow` (−, at request),
`coverage_sweetener_refunded` (+, on decline/expire/cancel), `coverage_earned` (+, via the
sweep). Migration `backend/scripts/migrate-personal-time.sql`, appended to
`backend/scripts/init-db.js`. All statements idempotent.

**Queries that must learn about `category`:** the `explicit` sum and `unclaimed` split in
`dashboard.js`, `getFamilyBudget.used_this_month`, both overlap checks in `scheduleActivity`
and `createRecurrence`, the `categorySplit` aggregate in `stats.js`, and
`runAutoCompleteSweep` (self activities have `coin_value = 0`, so they sweep harmlessly —
but they should not appear as completed *work*).

---

## 7. API

New router `backend/src/routes/personalTime.js`, mounted with
`requireAuth, perUserLimiter, familyHeartbeat`; logic in
`backend/src/services/personalTimeService.js`, following the
`(client, userId, …) → { data } | { error: { code, message } }` contract.

| Method | Path | Description |
|---|---|---|
| GET | `/api/personal-time?familyId=` | Mine, awaiting me, recent history |
| POST | `/api/personal-time/quote` | Live pricing for the dialog: baseline, counterparty conflicts, my balance |
| POST | `/api/personal-time` | Create; escrow sweetener; notify counterparty |
| POST | `/api/personal-time/:id/accept` | Materialize the linked pair; carry sweetener onto the coverage row |
| POST | `/api/personal-time/:id/decline` | Refund; notify requester |
| DELETE | `/api/personal-time/:id` | Withdraw; refund |

**Validation:** duration 15 min – 24 h; starts in the future; requester free in that window;
sweetener ≤ requester's balance. Counterparty conflicts are **warnings, not errors**.

**Also changes:** `POST /api/absences` gains the 24 h minimum, with a message pointing at
personal time for anything shorter.

**Notifications** (`prefKey: 'coverage_requests'`): request received → counterparty;
accepted/declined → requester; expiring within 6 h → counterparty.

---

## 8. UI (Flutter)

**Double-tap to create (`daily_screen.dart`).** The hour grid has a `DragTarget` and no tap
handler, so `onDoubleTap` is free of gesture conflicts. Reuse the existing `_onGridDrop`
math — `localDy → kGridHeight → 30-minute slot` — to seed the start time. Fields: **name**,
**duration** (30 min – 12 h, default 60), **short note**, **coverage toggle**, **sweetener
stepper** with a live quote: *"Ana gets 2 cc + your 5 cc. Your balance after: 43 cc."*

Double-tap is invisible, so pair it with a **"Personal time"** row in the existing `+` sheet
and a **＋ hint on the free-time gap blocks** the timeline already renders for gaps ≥ 30 min.

**Ghost blocks.** Pending requests render dashed and muted on both calendars — *"Awaiting
Ana"* / *"Pablo asked you to cover"*. The daily screen already merges activities and
absences into one timeline; this is a third list. Blocks over ~12 h or crossing midnight
render as an all-day chip.

**Visual language for the subclasses.** Care and self must be legible at a glance —
`getCardStyle` maps status to colour today; `category` needs its own treatment (self activities
outlined rather than filled, no coin badge).

**Response card.** Dashboard, beside the existing offers strip: *"Pablo wants Friday
18:00–19:30 for the gym. Covering Leo pays you 2 cc + 5 cc from Pablo."* → Accept / Decline.

**Absence dialog** becomes a date-range picker with the 24 h floor, and should now say what
it costs: *"While you're away, your share of the monthly coins goes to whoever is home."*

**Also:** ledger labels (`profile_screen.dart:830`) and flow colours
(`stats_screen.dart:508`) for the three new reasons; notification toggle at
`profile_screen.dart:62`; strings in all four locales; glossary entries for *care activity*,
*self activity*, *coverage* and *sweetener* in `widgets/help_sheet.dart`.

---

## 9. Phases

Seven slices. Each one ends in a state you could ship and stop at.

| Phase | Goal | Depends on |
|---|---|---|
| **1 — Absence floor** | Absences mean "away for at least a day" | — |
| **2 — Presence-weighted residual** | An absent caretaker's share goes to whoever is home | — |
| **3 — Activity subclasses** | The model can express "this is not a contribution" | 2 |
| **4 — Backend core** | The negotiation works end to end over the API | 3 |
| **5 — Flutter core** | The feature is usable | 4 |
| **6 — Recurrence & expiry** | "Every Friday" works; stale requests clean up | 5 |
| **7 — Fairness surfacing** | Personal time is as visible as contribution | 5 |

**Phases 1 and 2 are a standalone fairness fix** — worth doing whether or not the rest ever
ships, because today a caretaker can be away three weeks and still collect half the
unclaimed coins. **Phase 3 is an invisible refactor.** **Phases 4–5 are the feature.**
**Phases 6–7 are completion.**

---

### Phase 1 — Absence floor ✅ implemented

**Goal.** Make an absence mean "away for a day or more", so discretionary short time has
somewhere else to go.

**Changes.**
- `POST /api/absences` (`routes/absences.js:45`) — 24 h minimum, checked alongside the
  existing `end_time > start_time` guard, with a 400 that explains the whole-day rule.
- `absences_min_duration` CHECK added `NOT VALID` — binds new rows, grandfathers the short
  absences already in live databases (§5.1).
- `widgets/absence_dialog.dart` — the two datetime pickers and the 09:00→17:00 default
  become a **date-range picker** defaulting to today → tomorrow. The current default would
  be invalid under the new floor, so this is not optional polish.
- Copy in all four locales, including the new rejection message.

**Done when.** A sub-24 h absence is rejected with a message explaining the whole-day rule;
existing short absences still list and delete; the dialog cannot produce an invalid range.

**As built.**
- `src/services/absenceService.js` — `MIN_ABSENCE_HOURS` and the pure
  `validateAbsenceWindow`, following the `validateStarterTasks` precedent so the rule is
  unit-testable without a database. `routes/absences.js` calls it in place of its inline
  `end > start` check.
- `scripts/migrate-absence-floor.sql` — the `NOT VALID` constraint, guarded by a
  `pg_constraint` lookup so `db:init` stays re-runnable. Registered in `init-db.js`;
  `schema.sql` carries a comment pointing at it.
- `widgets/absence_dialog.dart` — rewritten around `showDateRangePicker`. The window math
  is extracted as `absenceWindowFromRange` so the "cannot produce an invalid range"
  guarantee is a test, not a claim. The anchor day is clamped into the picker's bounds,
  since the Daily view scrolls arbitrarily far.
- Copy: `absenceDatesLabel`, `absenceDaysCount`, `absenceWholeDaysNote` in all four
  locales, replacing the now-unused `fromLabel` / `toLabel`.

**The rejection copy does not name personal time yet.** Phase 1 ships before that feature
exists, so pointing at it would advertise something users cannot find. The message states
the rule instead — *"Time off covers whole days: it must last at least 24 hours."* — and
should be revisited in Phase 5.

**Verified.** 7 new backend unit tests (121 total, all passing); 5 new Flutter tests (31
total); `flutter analyze` clean. The migration was applied against a throwaway Postgres 16
seeded with a legacy 8-hour absence: the old row still reads and deletes, a new 8-hour
insert is rejected by the constraint, exactly 24 h is accepted, and `db:init` runs twice
cleanly with `convalidated = f`.

---

### Phase 2 — Presence-weighted residual ✅ implemented

**Goal.** The coins for hours you were away go to the caretaker who was present (§3.1).

**Changes.**
- **First, a pure refactor, committed on its own:** lift the distribution block out of
  `dashboard.js:17–95` into `services/distributionService.js` with no behaviour change.
  It currently sits inside a GET route, holds `FOR UPDATE` on the family row and loops
  over every elapsed month — it needs to be testable before anything is added to it.
- Replace `floor(unclaimed / caretakers.length)` with the presence weighting.
- Add a per-caregiver absent-hours query, clipped to the month being swept (an absence can
  straddle a month boundary).
- Guards: `Σ presentHours = 0` falls back to the even split; a caregiver who joined
  mid-month counts present hours only from `family_members.joined_at`; keep flooring each
  share and leaving the rounding remainder unspent, as the code does today.
- `absence_dialog.dart` gains a line saying what it costs: *"While you're away, your share
  of the monthly coins goes to whoever is home."*

**Done when.** Unit tests cover: total is conserved; nobody absent reproduces today's even
split exactly; everyone absent falls back; a single caregiver takes everything; a
mid-month joiner is prorated. The ledger still writes `monthly_distribution`.

**As built.** Two commits, as planned.

1. *Extraction.* `services/distributionService.js` holds the block verbatim; the route is
   now one line, `if (!await runMonthlyDistribution(client, familyId)) return null;`. The
   only addition is an injectable `now`, so tests do not drift with the wall clock. Ten
   characterization tests pinned the old behaviour first.
2. *Weighting.* Two exported pure functions do the work — `presentHours`, which merges a
   caregiver's absences (overlapping trips cannot subtract the same hour twice) and counts
   a mid-month joiner only from `joined_at`; and `distributionShares`, which floors every
   share, leaves the rounding remainder unspent, and falls back to an even split when
   nobody was present. All ten characterization tests still pass untouched, which is the
   regression guarantee: with nobody away, the split is bit-for-bit what it was.

Absences are merged in JS rather than SQL deliberately — a family has a handful per month,
and the repo's mock-client tests can exercise a JS rule but not a window function over
`tstzrange`s.

The absence dialog now says what time off costs: *"While you're away, your share of the
monthly coins goes to whoever is home."*

**Verified.** 149 backend tests (28 in this file), 31 Flutter tests, `flutter analyze`
clean. End-to-end against a real Postgres 16: a family with 744 h of July GDP, 200 already
claimed and one caregiver away three days settled to **258 / 285** — the traveller down 14
coins from the old even split of 272, the caretaker who stayed up 13, one coin unspent to
rounding, and the clock advanced exactly once.

---

### Phase 3 — Activity subclasses ✅ implemented

**Goal.** Land the model change on its own, with no user-visible behaviour, so the risky
refactor is not entangled with a new feature.

**Changes.**
- `category` column with `DEFAULT 'care'`, the compound category/type CHECK, and the
  `description` column (§6).
- The overlap matrix (§4.1) in both `scheduleActivity` and `createRecurrence` — including
  the `care × coverage` cell that must be **allowed**.
- Make every aggregate `category`-aware: the `explicit` sum in `distributionService`,
  `getFamilyBudget.used_this_month`, and `typeSplit` in `stats.js`. Self activities
  carry `coin_value = 0`, so they sweep harmlessly — but they must not appear as completed
  *work*.
- Card treatment for `category` in the Flutter timeline: self activities outlined rather
  than filled, no coin badge. `getCardStyle` maps status to colour today; `category` is a
  second axis.

**Done when.** Every existing test passes unchanged, and a hand-inserted `category='self'` row
moves no coins and appears in no budget, GDP or stats figure.

**As built.** `scripts/migrate-activity-subclasses.sql` renames `category` → `type`, adds
`category` (the subclass, DEFAULT `'care'`, so every existing row is correct with no
backfill) and `description`, swaps the inline category CHECK for one vocabulary per
category, and indexes `(family_id, category, status)` since every work aggregate filters
on it. It is idempotent and converges from three starting shapes: a database built from the
current `schema.sql`, one predating the subclasses, and one that ran the interim revision
where the subclass was called `kind`.

Eleven queries became `category`-aware: the GDP residual in `distributionService`, the two
budget figures (`getFamilyBudget`, the dashboard's `used_this_month`), the budget warning
in `scheduleActivity`, and six stats aggregates (lifetime KPIs, `trendByMonth`,
`typeSplit`, `activityFrequency`, `completionRates`, `statusDistribution`).
`listActivities` now returns `category`, `type` and `description` so clients can tell the subclasses
apart. `runAutoCompleteSweep` was deliberately left alone: a self activity is worth 0, so
it sweeps to `completed` and moves nothing.

The dashboard's day-by-day calendar counts was **not** filtered — it is a schedule, not a
work metric, and personal time genuinely occupies the day.

The wire format follows the model: `POST /api/activities` takes `type`, `listActivities`
returns `category` and `type`, the starter-task payload sends `type`, and the stats payload
key is `typeSplit`.

Flutter: `isSelfActivity` in `ui.dart` is the single predicate both renderers share; a row
with no `category` is care work, which keeps every pre-migration row rendering as it did.
Personal time never takes the filled "completed work" fill — it earns nothing, so it reads
as a claim on the day — and `_ActivityAction` returns nothing for it, since personal time
is nobody's to validate, delegate or take over.

**The overlap matrix is complete.** `coverage` became a care *type* rather than a property
inferred from a foreign key, so the exemption landed here rather than waiting for the
requests table: both overlap checks carry `AND type <> 'coverage'`. The rest of the matrix
already held, because those checks are subclass-agnostic — a self activity blocks care work
in the same window and vice versa, which is correct.

**Verified.** 150 backend tests, 35 Flutter tests, `flutter analyze` clean. Against a real
Postgres 16: the migration converges on the identical shape from all three starting states,
with existing rows becoming `care/care` and `care/household`; `db:init` runs twice cleanly;
all five self types insert; and the constraint rejects self borrowing a care type, care
borrowing a self type, self worth coins, an unknown category and an unknown self type.
A seeded self activity is invisible where it must be — lifetime tasks 1 rather than 2,
status distribution 1 rather than 2, and the split free of the `null` bucket it would
otherwise add to the chart.

**Caught during that check:** an earlier draft made `type` nullable for self activities, and
the CHECK then let a care row with a null type through — `(category = 'care' AND type IN
(…))` evaluates to NULL rather than false, and a CHECK rejects only on false. Giving self
activities their own types made both columns NOT NULL and removed the hole structurally.

---

### Phase 4 — Backend core ✅ implemented

**Goal.** The full negotiation — request, quote, accept, decline, withdraw — over the API,
single instances only.

**Changes.**
- `personal_time_requests` table, `counterpart_activity_id` and
  `personal_time_request_id` on `activities` (§6).
- `services/personalTimeService.js` and `routes/personalTime.js`, mounted in `app.js` with
  `requireAuth, perUserLimiter, familyHeartbeat` like every other router.
- The `/quote` endpoint the dialog needs: baseline price, counterparty conflicts as
  warnings, requester's balance.
- Escrow on create and refund on decline / expire / withdraw, reusing the two statements
  `offerBounty` already runs.
- Materialize the linked pair on accept, carrying the sweetener onto the coverage row's
  `bounty_amount` so `runAutoCompleteSweep` pays it with no new payout code.
- `coverage_requests` preference column, accepted by the notification-preferences route,
  and the four notification sends (§7).

**Done when.** Money-path tests pass: sweetener escrowed on create and refunded on all
three failure paths; concurrent accepts cannot double-materialize (`FOR UPDATE` on the
request row); coverage pays baseline + sweetener exactly once through the sweep; a declined
request leaves zero `activities` rows; self activities never contribute to `explicit`.

**As built.** `scripts/migrate-personal-time.sql`, `services/personalTimeService.js` and
`routes/personalTime.js`, mounted alongside the other routers. The service keeps its rules
pure where it can — `validateSelfWindow`, `priceCoverage`, `expiryFor` are testable without
a database — and every state transition takes `FOR UPDATE` on the request row inside
`withTransaction`.

Counterparty resolution needs no picker in the common case: with two caregivers it is the
other one, with three or more an unnamed counterparty means "ask anyone". A request that
needs no coverage (§4.7) is created already `accepted` with `responded_by` NULL, books the
self activity immediately, and moves no coins.

The coverage shift is inserted directly rather than through `scheduleActivity`, so it is
free to overlap whatever the coverer already has on — the second half of the overlap matrix,
handled by construction. The one thing that blocks accepting is being *away*: an absence
overlapping the window is refused, because you cannot cover a dependent from another city.

**One deviation from the plan.** §6 promised a `coverage_earned` ledger reason while Phase 4
promised the sweep would pay "with no new payout code". Running it end to end showed why
both matter: reusing `bounty_amount` works perfectly, but the wallet then reads *"bounty
earned"* for what was actually *"you covered Leo so Ana could go to the gym"*. `db/ledgerReasons.js`
resolves it — one map from activity type to reason strings, used by the sweep,
`completeActivity`, `validateActivity` and `revertActivity`. No new payout path, correct
labels. Reverting had to learn it too: matching the wrong reason would have left the ledger
showing a credit the balance no longer has.

**Verified.** 181 backend tests (30 new), 35 Flutter tests, `flutter analyze` clean. End to
end against Postgres 16, with a real family: the sweetener leaves the requester's wallet at
request time and nothing is booked; accepting materializes the linked pair with the baseline
as `coin_value` and the sweetener as `bounty_amount`; **the coverer then successfully
scheduled a household task inside their own coverage window**; the sweep paid 2 + 5 exactly
once and a second sweep paid nothing; declining refunded the escrow and left zero activity
rows; and reverting a coverage shift wrote `coverage_reverted` rather than
`activity_reverted`.

**Found here, fixed later:** `revertActivity` rewrote the original credit row into a debit
instead of appending a reversal, so the ledger netted 2× the reverted amount below the real
balances. It now appends, and `scripts/migrate-ledger-reversals.sql` restores the credits the
old code swallowed.

---

### Phase 5 — Flutter core ✅ implemented

**Goal.** The feature is usable by a real family.

**Changes.**
- `onDoubleTap` on the Daily hour grid, reusing the `_onGridDrop` slot math, opening the
  dialog: name, duration, note, coverage toggle, sweetener stepper with the live quote.
- Two discoverable entry points alongside it — a "Personal time" row in the `+` sheet, and
  a ＋ hint on the free-time gap blocks (§8).
- Ghost blocks for pending requests on both calendars; the all-day chip for blocks over
  ~12 h or crossing midnight.
- The accept/decline response card on the Dashboard.
- Ledger labels (`profile_screen.dart:830`), stats flow colours
  (`stats_screen.dart:508`), the notification toggle (`profile_screen.dart:62`), strings in
  four locales, and glossary entries for *care activity*, *self activity*, *coverage* and
  *sweetener* in `help_sheet.dart`.

**Done when.** A two-device run completes: create → the other device is notified → accept →
the pair appears on both calendars → the sweep pays baseline + sweetener.
*(Run on 2026-08-26 — see **Two-session verification** at the end of this section.)*

**As built.** `widgets/personal_time_dialog.dart` is the create sheet: title, the five self
types as chips, start and duration, an optional note, the coverage toggle, and a sweetener
stepper capped at the requester's balance. It never invents a number — the baseline, the
counterparty's name, the wallet balance and any conflicts all come from `POST /quote`, so
the sheet cannot disagree with the API about what a window costs.

Three ways in, because a double-tap nobody knows about is a feature nobody uses: the
gesture itself on the hour grid (`onDoubleTapDown` remembers the slot, `onDoubleTap` opens
the sheet, sharing the drag-drop maths so both land on the same times), a **Personal time**
row at the top of the `+` sheet, and the free-time gaps in the timeline, which now read
*"1h free · take it for yourself"* and are tappable.

Pending requests show on both Daily layouts and can be answered from either the chip dialog
or the Dashboard card. Declining is exactly as prominent as accepting, and nothing anywhere
counts refusals.

**Deviation: chips, not ghost blocks.** Pending requests render in the day strip beside
absences rather than as positioned blocks in the timeline. A request is not an activity —
nothing is booked until someone accepts — and the mobile list is the primary surface, where
a positioned ghost would have meant teaching the timeline builder two row shapes. The chips
carry the same information and are tappable. Positioned ghosts on the desktop grid remain
worth doing.

**Also not done:** the all-day chip for blocks over ~12 h. The duration picker stops at 12 h
so nothing can exceed the grid, but a long block starting late still renders truncated at
midnight rather than as a chip.

**Verified.** 38 Flutter tests (3 new, including a widget test that pumps the sheet and
asserts the window is seeded from the tapped slot and that coverage is requested by
default), 181 backend tests, `flutter analyze` clean. The Daily screen's request fetch is
deliberately defensive — `Future.wait` fails fast, and a hiccup on the newest endpoint must
not blank out the whole day.

**Two-session verification (2026-08-26).** The exit criterion was run against a local stack
rather than left on trust: Postgres in Docker, the **Firebase auth emulator** for identity,
the real backend (`npm run dev:test`), and two users minted straight from the emulator's REST
API — two genuinely independent sessions with real ID tokens, driving the real HTTP API.

Twenty assertions, all passing: Ana asks → the sweetener is escrowed and leaves her wallet →
Ben, in his own session, sees one pending request addressed to him and knows who is asking →
Ana is refused covering her own personal time → Ben accepts → one pair materializes → her
calendar carries the self activity worth zero and his the coverage shift, each row pointing
at the other → the ordinary auto-complete sweep pays Ben baseline + sweetener, and does not
charge Ana twice.

**Still unproven: the push banner actually arriving.** FCM has no emulator, and registering a
web token needs Chrome's native notification permission, which cannot be automated. The
*send* path was verified separately against a deliberately invalid token, which surfaced
something worth knowing:

> **`npm run dev:test` cannot send a push at all, and fails silently.** With
> `FIREBASE_AUTH_EMULATOR_HOST` set, `middleware/auth.js` passes `credential: undefined` to
> `initializeApp`; firebase-admin falls back to Application Default Credentials, finds none,
> and dies reaching `metadata.google.internal` (`app/invalid-credential`). Every send in
> `utils/notify.js` sits inside a try/catch, so the symptom is no push *and* no error. Adding
> `GOOGLE_APPLICATION_CREDENTIALS=firebase-credentials.json` makes FCM authenticate and reject
> only the bad token. Anyone debugging silent notifications locally should check this first.

One assertion in that run failed and was **my test's error, not the code's**:
`listActivities` does not select `counterpart_activity_id`, so it read as null over HTTP
while being correctly set in both directions in the database. The app never reads that
column — it is a backend integrity link — so nothing needs exposing.

---

### Phase 6 — Recurrence & expiry ✅ implemented

**Goal.** "Every Friday at the same time", and requests that clean themselves up.

**Changes.**
- Honour `recurrence` / `recurrence_until` on accept: materialize N pairs, skip instances
  where the counterparty is unavailable, and report the created count — mirroring what
  `createRecurrence` already does.
- Expiry sweep at `min(request + 48 h, starts_at)`, refunding the sweetener, run from
  `runAutoCompleteSweep` since it already executes inside every activity list call.
- "Ask anyone" mode for families with three or more caregivers: first to accept wins, the
  rest see the request close.

**Done when.** A weekly request until a date creates the right number of pairs and reports
the skips; an unanswered request expires and the sweetener returns to the requester.

**As built.** `occurrencesFor(startsAt, endsAt, recurrence, until)` in
`personalTimeService.js` is pure and returns `{ occurrences, error }`, capped at
`MAX_OCCURRENCES = 60`. It starts *at* the seed — unlike `createRecurrence`, which excludes
its own instance because that one already exists — and mirrors that function's server-local
`setDate` stepping, inheriting its DST caveat. It does not inherit its date-only parsing
bug: `endOfDay` reads `YYYY-MM-DD` as a local day, so the boundary falls on the same date on
every machine.

The sweetener is priced **per occurrence and escrowed up front**: ten Fridays at 5 cc is ten
favours asked, so the whole 50 leaves the wallet at creation. `escrowed_coins` (new column,
added to `schema.sql` and `migrate-personal-time.sql` with a backfill for rows predating it)
records what actually left, separately from the per-occurrence `sweetener_coins`. Refunds
read that column instead of recomputing an occurrence list, and write it down as they pay —
which is also what makes the expiry sweep idempotent. `POST /quote` now takes the recurrence
and returns `occurrences`, so the sheet shows the true total without inventing a number.

`acceptRequest` materializes a pair per occurrence, skipping any where the accepter is away
or the requester has since filled the window, and refunds `sweetener_coins × skipped`. A
series nobody can make at all is **refused**, not accepted empty: the request stays pending
with its escrow intact so someone else can still take it. It returns `{ created, skipped,
refunded }`, and both accept paths in the app report the count when anything was skipped.

`expireStaleRequests` runs from `listRequests`, **not** from `runAutoCompleteSweep` as this
plan originally said — the personal-time domain sweeping its own stale rows is cleaner and
runs just as often, since both calendars list requests. It shares the monthly distribution's
limitation: if nobody opens the app, nothing expires. That is acceptable because
`acceptRequest` already refuses an expired request, so the sweep is about the money rather
than about correctness.

The create sheet gained a repeat chip row (`kPersonalTimeRepeats`, mirroring the API's
`RECURRENCES`) with an end date offered four weeks out rather than demanded, and the "ask
anyone" picker — a chip row of *Anyone* plus each candidate, shown only when
`candidates.length > 1`, because with two caregivers there is no decision to make.

Verified against Postgres 16, including the upgrade path from a database predating
`escrowed_coins`. 200 backend tests, 40 Flutter tests.

**Not done here.** Per-instance renegotiation of one occurrence in a series
(`parent_request_id` is still reserved and unwritten), and positioned ghost blocks for
pending requests on the desktop grid.

---

### Phase 7 — Fairness surfacing ✅ implemented

**Goal.** Personal time taken is as visible as contribution made — otherwise the release
adds a way to take without a way to see it (G10).

**Changes.**
- Stats: personal time taken vs coverage given, per member, beside the existing care-hours
  figures. Never a declined count (§10).
- `docs/PRODUCT.md` §15, the README feature list, `docs/database-schema.md` and the route
  table in `docs/backend.md`.

**Done when.** The docs describe the shipped behaviour, and a member can see at a glance
how much personal time each caretaker took this month.

**As built.** `routes/stats.js` gained a `fairnessByMonth` block: per member and month,
`personal_minutes` / `personal_count` from `category = 'self'` and `coverage_minutes` /
`coverage_count` from `type = 'coverage'`, over completed rows only — a session still to come
is not time taken. Nothing new is stored; both figures fall out of the Phase 3 subclass
columns. Every care aggregate already filtered `category = 'care'`, so personal time has
never inflated a contribution figure.

The stats screen shows it as a **Personal time & coverage** card in the Members section, two
bars per member scaled against each other, labelled with the latest month there is data for
rather than "now" — an empty card in the first days of a month would say nothing true. The
card carries the rule as a footnote: *saying no is never counted*.

**No declined count exists anywhere**, and the audit that says so is worth recording:
`declined` appears in the codebase only as a CHECK constraint value and in the notification
sent to the requester, who already knows. It is in no aggregate, no chart series, and no
Flutter string. `coinFlowByReason` does surface `coverage_sweetener_refunded` in the raw
payload, but that is a family-level monthly coin sum mixing declines, expiries, withdrawals
and skipped occurrences — it names no one, and `flowMeta` does not draw it.

Docs brought up to date: `PRODUCT.md` §15 (and the three missing push events in §12),
the README feature and schema tables, `docs/database-schema.md` (a new §22 for
`personal_time_requests`, and §6 `activities` corrected — it still described `category` as
`care|household`, which Phase 3 replaced), and `docs/backend.md` (§2, §3 and a
`/api/personal-time` route table; the documented `?month=` parameter on `/api/stats` was
removed because the route has never taken one).

Verified against Postgres 16: care work counts as neither taken nor given, an unfinished
session is not counted as taken, templates are excluded, and months group separately.

---

### Test coverage to add

Matching the existing convention that every coin path is unit-tested
(`backend/tests/`, mock-client style): presence weighting conserves the total, handles zero
present hours, and reproduces the even split when nobody is absent; sweetener escrowed and
refunded on decline, expiry and cancel; no double-materialization on concurrent accepts;
coverage pays baseline + sweetener exactly once; a declined request leaves zero
`activities` rows; **a care task scheduled inside a coverage window is not rejected**
(§4.1); self activities never contribute to `explicit`.

## 10. Risks

1. **The overlap matrix (§4.1)** — closed in Phase 3: `type = 'coverage'` is exempt from
   both overlap checks. The remaining half is that the accept flow must not reject a
   coverage row because the coverer already has tasks in that window.
2. **Double-counting self-activity hours (§3.2)** — if presence weighting ever includes them,
   the coverer is paid twice for the same hour.
3. **The distribution is a lazy sweep inside a GET route** (`dashboard.js`), holding
   `FOR UPDATE` on the family row and looping over every elapsed month. Adding per-caregiver
   absence queries inside that loop makes a slow path slower. Extract and test it in Phase 2
   before adding to it.
4. **Vocabulary load.** cc, bounty, validation, object of care, monthly budget — now plus
   *self activity*, *coverage*, *sweetener*. The help-sheet work ships in the same release,
   not after; see `docs/onboarding-help-plan.md`.
5. **"Bribe" is the wrong word in the UI.** Fine in conversation, corrosive in a product
   built on fairness — it frames a partner as purchasable. Ship it as *"sweeten the offer"*.
6. **Sweeteners as pressure.** Keep declining free and invisible — never surface declined
   counts on the dashboard or in stats.
