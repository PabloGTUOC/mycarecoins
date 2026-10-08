# Mobile UX Phase 3 — Implementation Brief (proposed)

> **For a coding agent working without prior context.** Phase 3 follows the second design
> critique of 2026-10-08 (`.impeccable/critique/2026-10-08T13-10-13Z__fluterfront-lib-screens.md`,
> 29/40, up from 22). Phase 2 (`docs/mobile-ux-phase2-brief.md`) rebuilt Today; Phase 3
> brings Me and Family to the same standard. Same ground rules as Phase 2: one commit per
> ticket on the working branch, no whole-file `dart format`, every new string in all four
> ARB files, tokens from `lib/theme/app_theme.dart`, Material 3 components,
> `flutter analyze` and `flutter test` clean. **No `backend/` changes.**

> **Status (2026-10-08):** proposed, not approved. Nothing here is built. The P1 from the
> critique (Family and Today disagreeing about what is waiting) is ticket P2-11 in Phase 2.

Decisions this brief rests on: coin balances **stay visible on the Family hub** (user,
2026-10-08); *Needs you* is **never a number** (D2); KPI cards stay, quieter (Phase 2).

## P3-1 · Me is one page (critique #2)

Today: a page heading with a subtitle, a purple gradient family banner, then a 3-way
segmented control (My Profile · Family · Wallet) with one panel at a time, a dark wallet
card headed "TOTAL BALANCE … COINS", and an "Activity Insights" card.

- No segmented control on phones. One scrolling page with three sections in this order:
  **Wallet**, **Family**, **You** (account, notifications, sign out, deletion). Section
  titles in sentence case. Deletion-request banners stay at the top when present.
- Remove the gradient banner. The family name and the user's alias become a plain line
  under the app bar title (`textSecondary`), not a card.
- Wallet: the balance is one row, "488 cc" in `textPrimary` at title size with "Your
  balance" as its label (no uppercase, no letter-spacing, no dark card), followed by the
  last three ledger lines and "See all" (opens the existing full ledger). The month
  picker and revert action keep working as today.
- "Activity Insights": keep only if it says something Stats does not; otherwise replace
  with a "See family stats" row that opens `statsRoute()`. (Open question 2.)
- `ProfileScreen.initialTab` callers (the coin pill opens the wallet) scroll to the
  Wallet section instead of switching tabs.
- Wide layout keeps its two columns; only phones lose the tabs.
- Tests: no SegmentedTabs on phones; section order; no `LinearGradient` in the screen;
  coin pill lands on Wallet; existing wallet/ledger tests pass.

## P3-2 · Family hub: compact members, no repetition (critique #3)

Today the first screen is a greeting paragraph, "Go to Today", the onboarding checklist,
then "Active Family Members" as a two-up card grid with a balance chip on each card,
pending member approvals, the week agenda, "Someone asked you to cover", offers, four KPI
cards and recent activity.

- Members: one compact list, a row per member (avatar, name, role, balance chip at the
  trailing edge), not a card grid. Balances stay (decision above); order by name, never
  by balance, and no "top" marker. Pending approvals stay in this section.
- Cover requests and offers are already in *Needs you* on Today. On Family, replace both
  sections with nothing (the greeting's P2-11 sentence links to Today), unless the user
  answers open question 1 otherwise.
- The checklist keeps its place and rules (caregivers, auto-hides once the loop ran).
- Section title "Active Family Members" → "Members" (sentence case).
- Tests: member rows (not cards) with balances, ordered by name; no cover/offer sections
  (if confirmed); checklist unchanged.

## P3-3 · Words and glyphs, the rest (critique #4)

- Sentence case for every heading and label still in Title Case or caps, in all four
  ARB files. Known: `dashActiveMembers`, `kpiTasksCompleted` ("Tasks Completed"),
  `newActivityBtn` ("+ New Activity"), `activityInsights`, `totalBalance`,
  `remainingThisMonth`, `totalMonthlyPool`, `estimatedRate`. Grep the ARB values for
  further Title Case labels and list them in the hand-back.
- Recurrence: replace the 🔁 glyph after titles (grid blocks, catalogue rows, sheet) with
  `Icons.repeat_rounded` at text size, `textSecondary`, with a Semantics label
  "Repeats" (localized).
- Coins: replace 🪙 in widget text with one small coin icon widget used everywhere a coin
  amount appears inline (tray chips, catalogue meta, KPI units if any).
- Tests: no 🔁 or 🪙 in widget code outside `landing_screen.dart` (scan test); the
  recurrence icon has its Semantics label.

## P3-4 · Tasks: create is not the headline (critique minor)

- "New Activity" moves from a full-width button above the filters to an app bar action
  (icon + tooltip) or a trailing text button in the filter row; the catalogue starts at
  the top of the screen.
- Tests: the create action exists and opens the existing form; no full-width button
  above the filters.

## Order

P2-11 first (Phase 2, the P1). Then P3-3 (strings and glyphs, touches many files, lands
before layout work), P3-1, P3-2, P3-4. Third critique after P3-4.

## Open questions (answer before P3-1 / P3-2)

1. Family duplicates *Needs you* (cover requests, offers). Remove them from Family, or
   keep them as a read-only summary?
2. "Activity Insights" on Me: remove in favour of a link to Stats, or keep and say what
   it adds?

## Hand back per ticket

Same as Phase 2: files changed, new ARB keys, `flutter analyze` and `flutter test`
results, and anything in the ticket that conflicted with existing behaviour (keep the
existing behaviour and say so; do not remove copy the ticket does not name).
