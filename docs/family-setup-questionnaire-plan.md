# Family Setup Questionnaire — Plan

> **Status (2026-08-03): Stages A and B implemented.** Localized starter
> packs, the `starterTasks` API contract, the activity-areas questionnaire
> and the paged wizard are live on `main`. Stage C (telemetry + preference
> recording) is pending; see §Staging and the implementation logs at the end.
>
> This document was originally written on an abandoned branch. It was
> restored and updated for the current codebase — the problems it describes
> were still present verbatim.

Goal: improve the create-family wizard with a short questionnaire about
the kinds of activities the family wants, use the answers to (a) seed a
**relevant, localized** starter catalogue instead of today's fixed
English list, and (b) record what users actually want so the product can
learn from it.

## Why now — the two problems this solves

1. **Untranslated starter tasks.** `backend/src/db/defaultActivities.js`
   inserts ~21 hard-coded English template rows at family creation
   (`insertDefaultActivities`, called from `familyService.js`). They are
   database rows, not UI strings, so the gen-l10n work (docs/i18n-plan.md)
   can never reach them — a Spanish user gets "Breakfast prep" in an
   otherwise fully Spanish app.
2. **Blind seeding.** The current selection logic is a crude mapping from
   dependent types (child → 9 child tasks, pet → 3 pet tasks, household +
   generic always). Families with no pets still get "Doctor accompany";
   families who mostly need errands/admin get nothing for it, and we
   never learn what they wanted.

## Design

### 1. New wizard step: "What does care look like in your family?"

Insert one questionnaire step into the create-family flow, after
"Objects of Care". Deliberately small — two questions plus a preview:

- **Q1 — Activity areas** (multi-select chips, pre-checked from the
  dependents already entered):
  - 🍽️ Meals & cooking
  - 🧺 Cleaning & laundry
  - 🎒 Kids' routines & school runs *(pre-checked if a child was added)*
  - 📚 Homework & learning
  - 🐾 Pet care *(pre-checked if a pet was added)*
  - 🩺 Elder care & appointments *(pre-checked if elderly was added)*
  - 🧾 Errands & admin (shopping, paperwork) — *new pack*
  - 🌙 Night care *(babies; pre-checked if a child was added)*
- **Q2 — Starting point** (single choice):
  - "Start me with ready-made tasks" (default)
  - "Start empty — I'll create my own"
- **Preview list**: the starter tasks implied by Q1, each with a
  checkbox so individual tasks can be deselected before creation. This
  replaces today's take-it-or-leave-it 21-row dump and doubles as the
  create-family improvement: users see exactly what they'll get.

### 2. Client-side, localized starter packs

Move the starter **catalogue definition to the Flutter app** and send
the chosen tasks in the create-family payload:

- New `lib/data/starter_packs.dart`: packs keyed by area, each task as
  `(l10n key, category, durationMinutes, recurrent)`. Titles resolve
  through `AppLocalizations`, so the tasks are created **in the user's
  current app language** (~30 title keys × en/es/fr/de in the ARB files;
  the existing `untranslated.json` guardrail covers them).
- `POST /api/families` gains an optional `starterTasks: [{title,
  category, durationMinutes, isRecurrent}]` array. Backend inserts them
  verbatim as approved templates (same insert as today, but with the
  received titles). After creation they are ordinary user-editable
  content — consistent with the i18n-plan rule that user content is
  never machine-translated.
- **Fallback:** when `starterTasks` is absent (old clients, scripted
  tests), keep calling `insertDefaultActivities`
  unchanged. No DB migration; existing families keep their English
  titles as normal user content.
- Detail worth fixing in passing: seeded coin values currently use a
  flat 2 cc/hr while user-created tasks use the budget's
  `baseRatePerHour`. Compute starter-task coin values server-side with
  the same budget rule so the catalogue is consistent from day one.

### 3. Record the answers (the "understand what users want" part)

- Log a `setup_questionnaire` telemetry event (existing `Telemetry`
  service → `onboarding_events` table): selected areas, deselected task
  count, and the Q2 choice. No free text, no PII.
- Persist the selection on the family row (`activity_preferences`
  jsonb, added idempotently by db-init) so future features (suggestions,
  marketplace ideas) can use it.
- Extend `backend/scripts/onboarding-report.sql` with an
  area-popularity breakdown: which packs are chosen, which starter tasks
  get deselected most (those are the ones to rewrite or drop).

### 4. Create-family wizard polish (small, while we're in there)

- Convert the single long card into a **paged stepper** (1 Family
  details → 2 Caregivers → 3 Who you care for → 4 Starter tasks), with
  progress dots, per-step validation and Back/Next; wide layouts keep
  the current two-column shell around it.
- Validate caretaker invite e-mail format before submit; disable the
  submit button while the request is in flight.
- On success, land on the dashboard with the existing welcome dialog —
  the activation checklist's "Create a task template" step should
  auto-check when starter tasks were chosen, so new families start at
  step 2 (scheduling) instead of a fully unchecked list.

## Out of scope

- Re-translating starter tasks when the user later switches app
  language (they are user content once created).
- A questionnaire for families that already exist (could be a later
  "Suggested tasks" entry in Activities, fed by the same packs).
- Backend-side i18n of `defaultActivities.js` itself — it becomes a
  legacy fallback only.

## Test plan

- **Widget tests:** questionnaire step pre-checks areas from dependents;
  deselecting a task removes it from the payload; "start empty" sends an
  empty array (not absent!) so the backend skips legacy seeding.
- **Backend tests:** `POST /api/families` with `starterTasks` inserts
  exactly those rows (approved templates, budget-based coin values);
  with the field absent, legacy defaults still appear; with an empty
  array, nothing is seeded.
- **l10n:** `untranslated.json` stays empty across all four languages;
  per-locale widget test keeps passing.
- **Manual:** create a family in Spanish → catalogue titles appear in
  Spanish; onboarding report shows the questionnaire event.

## Staging

| Stage | Delivers | Effort | Status |
|---|---|---|---|
| **A — Packs + contract** | Fixes the untranslated-tasks bug; area selection derived from the dependents already entered in the wizard | ~1 day | ✅ done |
| **B — Questionnaire + wizard** | The activity-areas step, per-task preview with checkboxes, single card → paged stepper | ~1.5 days | ✅ done |
| **C — Learning loop** | Telemetry event, `activity_preferences` on the family row, popularity breakdown in `onboarding-report.sql` | ~2 h | pending |

Stage A is the whole user-visible fix and is low-risk: it changes what gets
seeded, not how anyone navigates. Stage B rebuilds the flow every new family
passes through, so it deserves its own review round and a look on a real
device. Stage C only pays off once B is collecting answers.

---

## Implementation log — Stage A (2026-08-03)

### Changes vs. the original plan above

Three deltas, decided when porting the plan to the current codebase:

1. **Real payload validation** (the original only checked `Array.isArray`).
   `starterTasks` now goes through `validateStarterTasks`: at most 40 items,
   title 1–100 chars, `category` in (`care`, `household`), integer
   `durationMinutes` ≥ 15, boolean `isRecurrent`. Without it a malformed
   payload reached the `activities` CHECK constraints and surfaced as a 500
   instead of a clean 400 — the client now supplies content that goes
   straight into the table, so it is validated like any other input.
2. **Budget-based coin values**, as flagged in §2 above. Starter tasks use
   `max(1, round(baseRatePerHour × minutes / 60))` — byte-for-byte the rule
   the activities screen suggests for user-created tasks
   (`_baseScore`/`_minCoins`), where `baseRatePerHour = monthly_coin_budget
   / 720`. The legacy path keeps its flat 2 cc/h so existing behaviour is
   untouched for old clients.
3. **Entitlement note** (postdates the original plan): plan limits currently
   cover members, actors and active rewards — *not* templates — so seeding
   is unaffected by a family's plan. If a `max_templates` limit is ever
   added to the catalogue, `insertStarterTasks` must respect it.

### What shipped

| Piece | Where |
|---|---|
| Starter catalogue, 22 tasks across 8 areas, localized titles | `fluterFront/lib/data/starter_packs.dart` + 22 keys × en/es/fr/de |
| Area derivation from dependents | `areasForDependents()` — meals/cleaning/errands always; child → kids' routines, homework, night care; pet → pet care; elderly → elder care |
| Wizard wiring | `onboarding_screen.dart` sends `starterTasks` built from the current locale |
| API contract | `POST /api/families` accepts optional `starterTasks`; absent = legacy English seeding, `[]` = start empty |
| Backend seeding | `insertStarterTasks` + `validateStarterTasks` in `backend/src/db/defaultActivities.js`, branched in `familyService.createFamily` |
| Tests | `backend/tests/starterTasks.test.js`, `fluterFront/test/starter_packs_test.dart` |

### Still true after Stage A

- Existing families keep their English titles — they are ordinary user
  content now, and no migration touches them.
- The legacy `insertDefaultActivities` path stays for clients that omit the
  field (old app builds, scripted API tests).
- Switching app language later does **not** re-translate already-created
  tasks, by design (see §Out of scope).

---

## Implementation log — Stage B (2026-08-03)

### What shipped

| Piece | Where |
|---|---|
| Paged wizard | `onboarding_screen.dart`: the single long card became 4 steps (family details → caregivers → who you care for → starter tasks) with a progress bar, "Step x of 4", Back/Next, and per-step validation |
| Questionnaire | Step 4 asks the starting point first, then the activity areas as multi-select chips (pre-checked from the dependents entered in step 3), then the preview |
| Per-task preview | Every implied task is listed with a checkbox, duration and a "Repeats" marker; the header counts what will be created |
| Start empty | Sends `[]` explicitly — the backend distinguishes that from an absent field, so "no tasks" never falls back to legacy English seeding |
| Exclusion plumbing | `starterEntries()`, `starterTaskKey()` and `starterTasksPayload(..., excluded:)` in `starter_packs.dart` |
| Validation | Caregiver e-mail format checked before leaving step 2 and again on submit; the submit button disables while the request is in flight |
| l10n | 20 new keys × en/es/fr/de (719 total per language) |

### Decisions taken during implementation

- **Starting point is asked before the areas.** The plan listed areas first,
  but a family choosing "start empty" should not have to scroll past choices
  that are about to be discarded — picking it collapses the rest of the step.
- **Area pre-checks re-derive when the dependents change.** Going back to
  step 3 and adding a pet re-runs `areasForDependents` and clears manual
  task exclusions; if the dependents are unchanged, manual edits survive.
  Tracked via `_derivedFromTypes` — without it, either the pre-checks go
  stale or every visit to step 4 wipes the user's choices.
- **Task checkboxes are keyed by `area:index`, not by title.** Titles are
  localized and would break the selection if the language changed mid-setup.
- **Submit re-validates every step**, not just the current one: the button
  is only reachable from step 4, but a future navigation change must not be
  able to create a family with a malformed caregiver invite.
- **Material icons instead of the emoji** listed in the plan, matching the
  rest of the app's iconography.
- **The activation-checklist item needed no work.** The dashboard computes
  `done: hasTemplate` from data, so seeding starter tasks auto-checks
  "Create a task template" already — Stage A satisfied that plan bullet.

### Verification status

Backend suite green (114/114 — Stage B is client-only). Script-verified:
four-locale key parity, every `l.*` key used by the wizard exists, ICU
plural placeholders consistent across languages, balanced delimiters.

**Not verified here — no Flutter SDK in the authoring environment.** Run
`flutter pub get && flutter analyze && flutter test` locally, then walk the
wizard once by hand:

1. Next/Back across all four steps; empty family name blocks step 1;
   a malformed caregiver e-mail blocks step 2.
2. Add a pet in step 3, return to step 4 → the pet-care chip is now
   pre-checked and the preview grew.
3. Uncheck two tasks → the header count drops and only the rest are created.
4. Choose "start empty" → the family is created with no activity templates.
5. Repeat in Spanish → chips, preview and created task titles are Spanish.
