# Personal Time & Coverage — handoff

> **Status: superseded — kept as the record of why things are the way they are.**
> Phases 6 and 7 are done (`2f7d2d0`, `7a7c7f6`, `bac1be6`), so §3 and §4 below are history
> rather than instructions. The living document is `docs/personal-time-plan.md`, which carries
> an **As built** section for every phase. What is still worth reading here: the model in §2,
> the two notes on the economy, and the known issues.

**Repo state at handoff:** `main` = `3948602`. **Now:** `main` = `bac1be6`, pushed to
`origin`; all seven phases complete.

---

## 1. Why this handoff exists

Partway into the first edit of Phase 6, the project directory became unreadable from the
session — `fatal: Unable to read current working directory: Operation not permitted`. It is
a macOS privacy (TCC) denial on the iCloud Drive folder, not a repo problem and not the
sandbox: it reproduced with sandboxing disabled, and `ls -d` on the path still resolved
while reading anything inside it failed.

**Fix:** grant your terminal (or Claude Code) access under
**System Settings → Privacy & Security → Files and Folders**, or Full Disk Access, then
restart the session.

### First thing to do in the repo

One edit was in flight when access was lost and may have half-applied — an `escrowed_coins`
column appended to `backend/scripts/migrate-personal-time.sql`, with the matching change to
`backend/src/db/schema.sql` never reached.

```bash
git status
git diff
```

**Resolved:** nothing had half-applied — the working tree was clean and the column did not
exist in either file. It was added properly in `2f7d2d0`, with a backfill for databases
predating it.

---

## 2. What is done

The feature works end to end: you can ask for personal time, the other caretaker is notified,
they accept or decline, and the coins move. Recurrence, expiry and the fairness reporting —
listed here as missing at the time of the handoff — have since been built.

| Phase | What it did | Commit |
|---|---|---|
| **1** | Absence floor — time off means a day or more | `9bbc011` |
| **2** | Presence-weighted residual — an absent caretaker's share goes to whoever was home | `af9fa26`, `b05f774` |
| **3** | Activity subclasses — `category` (care \| self) + `type` | `ca03cd8`, `f50fa29` |
| **3b** | Coverage became a care type, and may overlap | `7627010` |
| **4** | Request backend — quote, create, accept, decline, withdraw | `fceb74d` |
| **5** | The app — create sheet, pending chips, accept/decline card | `3948602` |
| **6** | Recurrence, per-occurrence escrow, expiry; repeat + "ask anyone" in the app | `2f7d2d0`, `7a7c7f6` |
| **7** | Fairness surfacing, and the docs brought up to date | `bac1be6` |

### The model, in the vocabulary we settled on

```
activities.category = 'care'  ->  type in (care, household, coverage)
activities.category = 'self'  ->  type in (sport, social, rest, appointment, other)
                                  coin_value must be 0
```

Both columns are `NOT NULL`. That is load-bearing, not tidiness: a CHECK rejects only on
*false*, so a nullable column makes an unmatched branch evaluate to NULL and the bad row
slips through. An earlier draft had exactly that hole.

`coverage` is written **only** by the accept flow — the API validator still accepts just
`care` and `household`, so nobody can create one by hand. It is the one type exempt from the
overlap check (`AND type <> 'coverage'` in `scheduleActivity` and `createRecurrence`),
because covering a dependent is supervision, not busy hands: the coverer still cooks dinner
inside that window.

### The two settlement paths

| | Absence (>= 24 h) | Self activity (< 24 h) |
|---|---|---|
| Settled | Month end, presence-weighted | Immediately, explicit counter activity |
| Refusable | No — you cannot decline a work trip | **Yes** |
| Sweetener | No | Yes, from the requester's wallet |

### Files that matter

| File | What it holds |
|---|---|
| `backend/src/services/personalTimeService.js` | The request lifecycle. Pure rules at the top (`validateSelfWindow`, `priceCoverage`, `expiryFor`) are unit-testable without a DB. |
| `backend/src/routes/personalTime.js` | The API, including `POST /quote`. |
| `backend/src/services/distributionService.js` | The monthly GDP residual, presence-weighted. |
| `backend/src/services/absenceService.js` | The 24 h floor. |
| `backend/src/db/ledgerReasons.js` | Activity type → ledger reason strings. |
| `backend/scripts/migrate-personal-time.sql` | The requests table. |
| `backend/scripts/migrate-activity-subclasses.sql` | `category`/`type`, idempotent from three starting shapes. |
| `fluterFront/lib/widgets/personal_time_dialog.dart` | The create sheet. |

### Two things about the economy that are easy to get wrong

1. **There are two coin layers, not one.** Explicit activities, *and* the monthly GDP
   residual in `dashboard.js` → `distributionService.js`. Because
   `unclaimed = totalGdp - explicit`, logging an activity does not create coins — it moves
   them from the shared residual to whoever did the work. Activities are **zero-sum** until
   `explicit` exceeds `totalGdp`. Never reason about coin flow from `activityService.js`
   alone.
2. **The real ceiling is `totalGdp`,** not `families.monthly_coin_budget`. The two are
   computed differently (fixed 720/360 per dependent vs. actual `daysInMonth x 24`) and
   disagree by 48 coins in February.

### Known issues, deliberately not fixed

- ~~**`revertActivity` corrupts the ledger.**~~ **Fixed:** it now appends a reversal row
  instead of rewriting the credit, and `scripts/migrate-ledger-reversals.sql` restores the
  credits that older reverts overwrote, so `SUM(amount)` matches the balances again.
- **`runAutoCompleteSweep` clears `bounty_amount` when it settles a shift**, so a later
  revert never returns the bonus — the person who reverted keeps the coins. Same task.
- **Pending requests render as chips, not positioned ghost blocks.** Deliberate: a request is
  not an activity, and on the mobile list a positioned ghost would mean teaching the timeline
  builder two row shapes. Positioned ghosts on the desktop grid are still worth doing.
- **No all-day chip for long self activities.** The duration picker stops at 12 h so nothing
  exceeds the grid, but a long block starting late renders truncated at midnight.
- **The two-device run: done except the banner.** Phase 5's exit criterion was run on
  2026-08-26 against the local stack — two real Firebase users from the auth emulator, two
  independent sessions, driving the real HTTP API. Create → escrow debited → the other
  session sees it addressed to them → the requester is refused covering their own → accept →
  the pair on both calendars → the ordinary sweep pays baseline + sweetener. What remains
  unproven is only the **push notification visibly arriving**: FCM has no emulator, and
  registering a token needs Chrome's native notification permission, which cannot be
  automated. See the note below before trying.
- **`npm run dev:test` cannot send push at all, and fails silently.** With
  `FIREBASE_AUTH_EMULATOR_HOST` set, `middleware/auth.js` passes `credential: undefined` to
  `initializeApp`; firebase-admin falls back to Application Default Credentials, finds none,
  and dies reaching `metadata.google.internal` with `app/invalid-credential`. Every send in
  `utils/notify.js` is wrapped in try/catch, so you see no push *and* no error. Export
  `GOOGLE_APPLICATION_CREDENTIALS=firebase-credentials.json` alongside it and FCM
  authenticates properly — verified both ways against a deliberately invalid token.

### Verification baseline

```bash
cd backend    && npm test          # 200 tests (181 at the time of the handoff)
cd fluterFront && flutter analyze && flutter test   # 40 tests (38 then)
```

The migrations were verified against a throwaway Postgres 16 rather than trusted:

```bash
docker run --rm -d --name cc -e POSTGRES_PASSWORD=test -e POSTGRES_DB=cc -p 55432:5432 postgres:16
cd backend && DATABASE_URL="postgres://postgres:test@localhost:55432/cc" npm run db:init
```

Run `db:init` twice — it must stay re-runnable.

---

## 3. ~~Pick up here~~ — Phase 6: recurrence & expiry ✅ done in `2f7d2d0`, `7a7c7f6`

> Built as specified below, with one deliberate divergence: `occurrencesFor` does **not** copy
> `createRecurrence`'s date-only parsing bug, only its `setDate` stepping. See the plan's
> Phase 6 **As built**.

**Goal.** "Every Friday at the same time", and requests that clean themselves up.

**Done when.** A weekly request until a date creates the right number of pairs and reports
the skips; an unanswered request expires and the sweetener returns to the requester.

The schema is already ready: `personal_time_requests` carries `recurrence`,
`recurrence_until` and `parent_request_id`. Nothing writes them yet.

### 3.1 The one decision to make first: how a series is priced

**Recommendation: the sweetener is per occurrence, escrowed up front.** Ten Fridays at 5 cc
means 50 cc leaves your wallet when you ask — you are asking for ten favours, not one. The
quote must show the total so it is never a surprise, and if it is unaffordable the answer is
to lower the sweetener, not to hide the cost.

That needs one new column, which is the edit that was in flight when access was lost:

```sql
-- backend/scripts/migrate-personal-time.sql, and mirrored in schema.sql
ALTER TABLE personal_time_requests
  ADD COLUMN IF NOT EXISTS escrowed_coins INTEGER NOT NULL DEFAULT 0
    CHECK (escrowed_coins >= 0);
```

`sweetener_coins` stays **per occurrence**; `escrowed_coins` records what actually left the
wallet. Refunds then never have to recompute an occurrence list to know how much to give
back — which matters, because a refund that recomputes is a refund that can drift.

### 3.2 Occurrence generation

Add a pure, testable function to `personalTimeService.js`:

```js
export const MAX_OCCURRENCES = 60;
export function occurrencesFor(startsAt, endsAt, recurrence, until) // -> [{start, end}]
```

- No recurrence → a single occurrence, the request's own window.
- `daily` / `weekdays` / `weekly`, starting **at** `startsAt` (unlike `createRecurrence`,
  which excludes its seed because that instance already exists — here nothing exists yet).
- Stop at `recurrence_until` end-of-day, or `MAX_OCCURRENCES`, whichever comes first. Reject
  anything longer with a clear message rather than silently truncating.
- **Mirror `createRecurrence`'s server-local date arithmetic** (`setDate`), including its DST
  caveat. Consistency with the existing convention beats a lone correct-but-different
  implementation. Note the caveat in a comment; do not fix it here.

### 3.3 `createRequest`

- Accept and validate `recurrence` / `recurrenceUntil`.
- Escrow `sweetener x occurrences.length`, store it in `escrowed_coins`.
- Refuse if the requester cannot afford the total, and write nothing.

### 3.4 `acceptRequest`

- Materialize a pair per occurrence, **skipping** any where either side cannot make it: the
  accepter is away, or the requester is already busy. Reuse `conflictsFor`.
- Refund `sweetener_coins x skipped` — the escrow was for favours that will not happen.
- Return `{ created, skipped }` so the UI can say so, mirroring what `createRecurrence`
  already reports.

### 3.5 Expiry

```js
export async function expireStaleRequests(client, familyId)
```

Pending requests with `expires_at <= NOW()` → refund `escrowed_coins`, set status `expired`.

**Call it from `listRequests`, not from `runAutoCompleteSweep`.** The plan originally said to
piggyback on the activity sweep; the personal-time domain sweeping its own stale rows is
cleaner and runs just as often, since both calendars now call `listRequests`. Same known
limitation as the monthly distribution: if nobody opens the app, nothing expires. That is
acceptable — `acceptRequest` already refuses an expired request, so the sweep is about the
refund, not about correctness.

### 3.6 "Ask anyone"

Mostly already works: `requested_of = NULL` means any active caregiver may accept, and
`acceptRequest` allows it. What is missing is the **picker** in the create sheet — when
`quote.candidates.length > 1`, offer a chip row of *Anyone* plus each candidate, and send
`requestedOf`. The others stop seeing the request naturally, because the UI filters on
`status = 'pending'`.

### 3.7 Tests to add

Money paths first, mock-client style, matching `backend/tests/personalTime.test.js`:

- `occurrencesFor`: weekly across a month; `weekdays` skips weekends; the cap holds; no
  recurrence yields exactly one.
- Escrow equals `sweetener x occurrences`, and an unaffordable series writes nothing.
- Accepting a series skips unavailable occurrences and refunds exactly `sweetener x skipped`.
- An expired request refunds `escrowed_coins` and leaves zero activity rows.
- Expiry is idempotent — sweeping twice must not refund twice.

Then verify against a real Postgres, the way Phases 2–4 were: a weekly request over a month
where the coverer has one absence should produce N−1 pairs and return one sweetener.

---

## 4. Phase 7 — fairness surfacing ✅ done in `bac1be6`

**Goal.** Personal time taken is as visible as contribution made. Without this the release
adds a way to take without a way to see it, which cuts against the whole premise.

- **Stats:** personal time taken vs. coverage given, per member, beside the existing
  care-hours figures. Both are already derivable — self activities carry
  `category = 'self'`, coverage carries `type = 'coverage'`.
- **Never a declined count.** Not on the dashboard, not in stats, not anywhere. Declining
  must stay free and invisible, or the sweetener becomes social pressure.
- Docs: `docs/PRODUCT.md` §15, the README feature list, `docs/database-schema.md`, and the
  route table in `docs/backend.md`.

---

## 5. ~~Suggested first commands~~ (historical)

```bash
cd "$HOME/Library/Mobile Documents/com~apple~CloudDocs/TFG/TFG"
git status && git log --oneline -8
cd backend && npm test
```

Then open `docs/personal-time-plan.md` and read §4 (the class model), §5 (the decisions) and
the Phase 6 section before writing anything.
