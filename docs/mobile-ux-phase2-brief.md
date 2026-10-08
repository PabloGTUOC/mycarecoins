# Mobile UX Phase 2 — Implementation Brief

> **For a coding agent working without prior context.** Phase 2 of
> `docs/mobile-ux-proposal.md`, reshaped by the design critique of 2026-10-06
> (`.impeccable/critique/2026-10-06T13-16-01Z__fluterfront-lib-screens.md`, score 22/40).
> Read `CLAUDE.md`, the proposal's §3–§4 and §6 decisions, and that critique first.
> Same ground rules as `docs/mobile-ux-phase1-brief.md`: one commit per ticket on the
> working branch, no whole-file `dart format`, every new string in all four ARB files,
> tokens from `lib/theme/app_theme.dart`, `flutter analyze` and `flutter test` clean.
> **No `backend/` changes**: where a ticket needs one, it says so and the lead does it.

> **Status (2026-10-08, 12:00 CEST):** P2-1, P2-2, P2-3a/b, P2-7, P2-8 done on branch
> `mobile-ux-phase1` (worktree `../mycarecoins-phase1`), not merged. P2-9 started by Antigravity,
> stopped on its quota with no edits made. See **Handoff** at the end.

Decisions this brief rests on (Today redesign confirmed 2026-10-07): tabs **Today · Family · Tasks · Rewards · Me** (D1);
*Needs you* shows **a dot, never a count** (D2); the checklist "complete" step ticks on
the **first payout** (D3); dark mode waits (D4); KPI cards **stay, quieter** (critique).

## P2-1 · Today tab and *Needs you* (critique #1, #3; proposal P1-1, P1-2)

- Bottom bar becomes Today · Family · Tasks · Rewards · Me. Today hosts the Daily screen
  as a tab (keep its week strip, FAB and AppBar actions; no back arrow when it is a tab).
  Tasks is the current Activities screen. Stats is no longer a tab.
- App opens on Today.
- Opening a day from Family switches to the Today tab on that day, instead of pushing a
  route without the bottom bar.
- Top of Today: a **Needs you** block listing only items addressed to the current user:
  validations they can give (`pending_validation`, not theirs, user is caregiver), cover
  requests asked of them or of anyone (status pending, not their own), pending member
  approvals (caregivers only), open offers they could take. One tap acts or opens the
  item. When empty it collapses to a single line, "You're all caught up."
- A small dot on the Today tab when *Needs you* is non-empty; never a number; cleared
  when Today is viewed. Semantics: the tab label gains ", needs your attention".
- Tests: tab order; Today is the initial tab; the empty and non-empty *Needs you* states;
  the dot appears and clears.

## P2-2 · Family hub, honest and quieter (critique #1, #8)

- The greeting must not claim "earned today" with the total balance (`dashEarned` is
  passed `totalCoins`). Use what the data supports: coins from activities completed
  today if computable from loaded data, otherwise reword to the balance ("The family
  holds {coins} cc") in all four languages.
- Week list: show today plus days that have something; collapse consecutive empty
  days into one line ("Free: Wed 7 – Mon 12"). Tapping a day goes to Today (P2-1).
- A "See stats" entry (Stats is no longer a tab), and the KPI cards open Stats.
- Quieter cards (`KpiCard` and the dashboard grid): sentence-case labels in
  `textSecondary` (no all-caps, no letter-spacing), values in `textPrimary`; colour only
  on a value that signals state. Applies wherever `KpiCard` is used, Stats included.
- Recent activity: hide "+0 cc" for personal time.

## P2-3 · Material 3 foundation, brand kept (critique #2, #3; replaces "less chrome")

Decided 2026-10-07: standard Material 3 components across the whole app, keeping the
CareCoins blue, Plus Jakarta Sans and the coin language. `useMaterial3` and
`ColorScheme.fromSeed` are already on; the gap is that almost every control is custom.

- Theme: complete `ThemeData` component themes (navigation bar, app bar, segmented
  button, filled/tonal/outlined/text buttons, chips, cards, bottom sheets with
  `showDragHandle`, time picker, snack bar) generated from the existing tokens. Success /
  warning ink and strong colours from T3 move into a `ThemeExtension` so widgets read
  them from the theme.
- Bottom bar: Material `NavigationBar` with `NavigationDestination`s; the D2 dot is the
  built-in `Badge` (small, no label). Keep labels always visible.
- Header: replace the pill header and the large page title + subtitle with a standard
  small top app bar per tab (title, help action, the balance as a compact action chip).
  Drop the logo on phones. Subtitles go, except on wide layouts if they earn it.
- `SegmentedTabs` → `SegmentedButton` (single selection). Rewards: Store and History in
  one list, Create as a button opening the form in a sheet. Tasks: Catalogue and Budget
  segments, New Activity as a button opening the form in a sheet.
- `VButton` keeps its API but renders `FilledButton` / `FilledButton.tonal` /
  `OutlinedButton` / `TextButton`; danger uses the error colour scheme.
- Cards: Material filled/outlined cards (tonal surfaces, no drop shadows).
- Time entry everywhere uses `showTimePicker` (no hour/minute dropdowns).

## P2-4 · Words and leaks (critique #4)

- Coverage rows are titled "Covering for {title}" in English by the server. Client-side,
  when `type == 'coverage'` and the title starts with that prefix, render a localized
  `coveringFor(title)` string. (The lead may later change the server to store the bare
  title; keep the client tolerant of both.)
- Wallet ledger: label `monthly_distribution` ("Monthly share" and translations).
- Me: remove the "FAMILY ID" pill from the banner.
- Charts: month axis labels via `DateFormat.yMMM(locale)` (short), not `2026-08`.
- Remove em dashes from user-facing ARB strings in all four languages (the date range
  "Oct 6 — 13" uses an en dash with spaces or "to").

## P2-5 · Stats leads with fairness (critique #5)

- Rename: "Performance Analytics" → "Family stats"; "Income Generation Trend" → "Coins
  earned per month"; "Lifetime coins" → "Coins from tasks" (all four languages).
- Move the fairness block (personal time taken vs coverage given) to the top of the
  Overview segment.
- Remove the corporate subtitle.

## P2-6 · Polish (critique minor observations)

- Catalogue: show a status pill only when a template is not approved; move delete into
  a swipe or an overflow menu instead of a red trash on every row.
- Me → Family: the remove × on a dependent appears only in an explicit edit mode.
- Empty day: hide the "0 / 0 done" bar when the day has no items; keep one call to
  action (the FAB), and make the empty-state text non-interactive.
- Budget: replace the semicircle gauge with a single labelled progress bar.

## P2-7 · Today: the hour grid on phones (Today brief, confirmed 2026-10-07)

The phone layout becomes the hour grid the wide layout already has (6:00 to 24:00),
not the card list.

- Activities are blocks sized by duration: title, assignee, coins; colour by category
  with the ink/strong tokens. Overlapping blocks (coverage) sit side by side.
- The red NOW line, opened in view; past hours slightly muted.
- Needs you folds above the grid into one line ("Validate Bath time, and 1 more" with
  an expand chevron); no count (D2).
- Absences render as a shaded band with "Ati away"; pending personal-time requests as
  dashed outline blocks at their time (replacing the chips).
- Keep the T1 week strip and the T4 semantics (each block one sentence).

## P2-8 · Today: the task tray and drag-to-schedule

- A `DraggableScrollableSheet` peeks above the navigation bar: a handle, "Tasks · drag
  onto the day", one row of task chips (most-scheduled first). Swipe up for the full
  library with search, category filter, and Time for me first.
- Long-press a chip (light haptic) to lift it; the tray collapses; a ghost block follows
  the finger, snapped to 15 minutes, labelled with its time range ("18:15 to 18:45");
  the grid auto-scrolls near the edges.
- Release schedules immediately, no dialog; a snack bar says "Bath time at 18:15" with
  Undo (Undo deletes the new instance).
- If the drop would conflict (person busy, person away, past time), the ghost turns
  error-coloured with the reason and the drop is refused.
- Non-drag path: tapping a chip opens `showTimePicker` and schedules at the chosen time.

## P2-9 · Today: quick add and the activity sheet

- Tap an empty hour: a small sheet "Add at 18:15" with the task list and Time for me;
  one tap schedules.
- Tap a block: a details sheet with the actions the user may take (Validate, Offer
  bounty, Take over, Repeat, Move, Remove), replacing the long-press and double-tap
  shortcuts as the primary path (keep them as shortcuts).
- Move: long-press a block and drag it to a new time, or Move in the sheet (time
  picker). Same permissions as removal: never coverage, never someone else's personal
  time, and not personal time whose coverage was accepted.
- **Backend (lead):** a reschedule endpoint, `PATCH /api/activities/:id/time`
  `{ startsAt }`, keeping duration, applying the removal permissions and the existing
  overlap rules (coverage exempt), upcoming statuses only.

## P2-10 · Today: states and alternatives

- Loading: a skeleton grid, not a spinner. Empty day: the grid with "Nothing planned.
  Drag a task here, or tap an hour." Past days: read-only (no drops, no tray drags).
  Error/offline: an inline message with Retry.
- Every drag has a tap path (P2-8, P2-9); screen readers get "double-tap to choose a
  time" hints on tray chips and blocks.
- The first-run tour points at the tray handle and an empty hour.
- Tests: snapping, conflict refusal, undo, quick add, the sheet's actions per role, the
  non-drag paths.

## Order

P2-1 (done) → P2-2 → P2-3 Material 3 foundation → P2-7 → P2-8 → P2-9 (with the lead's
endpoint) → P2-10 → P2-4 → P2-5 → P2-6 → second critique.

## Hand back per ticket

Files changed, new ARB keys, `flutter analyze` / `flutter test` results, and anything
not done with the reason.

## Handoff (for the next session)

**How the work runs.** Claude is lead developer and reviewer; the Antigravity agent in Orca
**terminal 2** (`term_1337af5f-18f8-4228-908a-0237f9eab8cf`, Gemini) writes the Flutter code.
Tickets are files in `.lead/` (gitignored, in the worktree): `P2-9.md` (with review notes
appended), `P2-10.md`, `P2-4.md`, `P2-5.md`, `P2-6.md`. Send a short pointer ("read
.lead/P2-x.md and implement it exactly"), not the ticket text. `.lead/watch.sh <marker>` polls
the terminal and exits on DONE / LIMIT / STALLED. Antigravity edits only `fluterFront/` in the
worktree and never commits. Claude reviews each ticket — diff, `flutter analyze`,
`flutter test`, response shapes against the backend, permissions against the server, a look on
the iOS simulator — fixes, and commits one commit per ticket. Backend changes are Claude's.

**Commits so far** (oldest first): T1–T5 and fixes (`3aeb76b` … `5cd2e5f`); personal-time and
coverage permissions `6d44a34`, `5c2bd9a`; critique + this brief `3e52652`, `b7531db`;
P2-1 `a9c31a5`; reschedule endpoint `0bd64fe`; P2-2 `1f64a44`; P2-3a `48fe2d9`; P2-3b `4652281`;
coverage/self bounty refusal `62d46ac`; P2-7 `7720a9d`; P2-8 `56f974b`; docs `4b1f2d1` and the
doc refresh after it. Backend 223 tests, Flutter 133 tests, all passing at P2-8.

**Next, in order:** P2-9 (resend the pointer once Antigravity's quota resets; it restores
Remove on phones, see `TODO(P2-9)` in `daily_screen.dart`) → P2-10 → P2-4 → P2-5 → P2-6 →
second impeccable critique (compare with 22/40) → a morning test checklist for the user
(drag gestures on the simulator) → ask the user before merging into `main`, pushing or deploying.

**Watch-outs learned in review.**
- `POST /api/activities/schedule` answers `{activity, warning}`; `PATCH /api/activities/:id/time`
  answers `{activity}`. Test fakes must use the real shapes (P2-8 shipped a broken Undo because
  a fake returned `{id}`).
- Show errors with `app.errorTextFor(e)`, never raw server text.
- No FAB on phone Today (it covered the tray); the tray's collapsed size is `kTrayCollapsed`.
- Coverage is never deleted, moved or bountied on its own; personal time only by its owner.
- To check a screen on the simulator: `flutter run` with
  `--dart-define=API_BASE=https://mycarecoins.app --dart-define=PURCHASES_ENABLED=false`, hot
  restart with `kill -USR2 <pid>`, and temporarily set `Shell(initialIndex:)` / `_dailyDate`
  to reach a state — restore before committing. The Dart MCP server (`dart mcp-server`) is now
  configured for Claude Code and should replace most of this.

**Open items outside this branch.**
- The branch's backend fixes are **not deployed**: production still lets a member delete
  another member's personal time and put coverage up for a bounty until it is.
- Google OAuth consent screen shows "project-1088534743968": set the app name in Google Cloud.
- The RevenueCat sandbox secret is in the repo; rotate it before production.
