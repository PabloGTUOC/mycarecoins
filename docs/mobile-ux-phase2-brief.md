# Mobile UX Phase 2 — Implementation Brief

> **For a coding agent working without prior context.** Phase 2 of
> `docs/mobile-ux-proposal.md`, reshaped by the design critique of 2026-10-06
> (`.impeccable/critique/2026-10-06T13-16-01Z__fluterfront-lib-screens.md`, score 22/40).
> Read `CLAUDE.md`, the proposal's §3–§4 and §6 decisions, and that critique first.
> Same ground rules as `docs/mobile-ux-phase1-brief.md`: one commit per ticket on the
> working branch, no whole-file `dart format`, every new string in all four ARB files,
> tokens from `lib/theme/app_theme.dart`, `flutter analyze` and `flutter test` clean.
> **No `backend/` changes**: where a ticket needs one, it says so and the lead does it.

Decisions this brief rests on: tabs **Today · Family · Tasks · Rewards · Me** (D1);
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

## P2-3 · Less chrome, fewer nested tabs (critique #2, #3)

- Phone header: drop the logo/wordmark; keep help and the balance; reduce its height.
- Page titles: one line at a smaller size; remove the subtitle paragraphs on phones
  (keep them on wide layouts).
- Rewards: Store and History become one scrolling list (store first, then a "History"
  section); Create becomes a button that opens the existing form in a sheet. No
  segmented control.
- Tasks: keep Catalogue and Budget as segments; New Activity moves to a button on
  Catalogue that opens the form in a sheet.

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

## Hand back per ticket

Files changed, new ARB keys, `flutter analyze` / `flutter test` results, and anything
not done with the reason.
