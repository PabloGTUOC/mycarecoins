---
target: mobile app after Phase 2
total_score: 29
p0_count: 0
p1_count: 1
timestamp: 2026-10-08T13-10-13Z
slug: fluterfront-lib-screens
---
# Critique — CareCoins mobile app (after Phase 2)

Target: `fluterFront/lib/screens`, iPhone 17e simulator, production data (read-only), 2026-10-08.
Previous: 2026-10-06, 22/40.

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | Skeleton, Undo SnackBars, Needs you; but Family says "4 tasks waiting" while Today says "all caught up" |
| 2 | Match system / real world | 3 | Corporate copy and data leaks fixed; "TOTAL BALANCE … COINS", "Junior Explorer", "Activity Insights" remain |
| 3 | User control and freedom | 3 | Today is a tab; Undo on schedule and move; Stats has a back button; edit mode for removals |
| 4 | Consistency and standards | 3 | Material icons and M3 components throughout; Title Case vs sentence case, 🔁/🪙 glyphs, one gradient banner |
| 5 | Error prevention | 3 | Drag refusals, read-only past days, delete behind menu + confirm, server-matching permissions |
| 6 | Recognition rather than recall | 3 | Activity sheet shows every action as a button; long-press drag is the only hidden gesture and has tap alternatives |
| 7 | Flexibility and efficiency | 3 | Drag, tap-an-hour, time picker, one-tap Validate pills |
| 8 | Aesthetic and minimalist design | 2 | Today, Tasks, Rewards are calm; Family and Me still carry the dashboard grammar |
| 9 | Error recovery | 3 | Inline error with Retry on Today, localized errors everywhere |
| 10 | Help and documentation | 3 | Tour retargeted to the tray and an hour; help sheet; checklist |
| **Total** | | **29/40** | **Good** (was 22, Acceptable) |

## Anti-patterns verdict

LLM: Today no longer reads as a template: an hour grid with a tray is a committed,
product-specific shape. The generic-dashboard grammar survives in two places: Me (purple
gradient family banner, dark "TOTAL BALANCE 488 COINS" hero card with an uppercase
tracked label, a 3-way segmented control) and Family (a member card grid with balances
under the checklist, which leans toward the leaderboard PRODUCT.md rejects). Stats keeps a
KPI card row under the fairness card.

Deterministic: `detect.mjs` on `fluterFront/web` returns 0 findings (was 1 em-dash
finding in privacy.html, fixed in P2-4); it returns nothing for Dart. Code scans stand in:
63 emoji glyphs in widget code (was 65; 26 are on the landing page, a brand surface) and
51 raw `Color(0x…)` outside the theme (was 57). No browser overlay: the target is a
Flutter app on the iOS simulator, with no DOM to inject into.

## What's working

- Today: the hour grid, the tray and tap-an-hour make "plan my day" one gesture; the
  empty day is one quiet line instead of a call-to-action stack.
- The activity sheet: every action is a labelled full-width button, filtered to exactly
  what the server allows; the destructive one is last and red.
- Stats leads with fairness and says it in a sentence ("You covered 7 h 30 for Ati and
  took 6 h for yourself"), with the "saying no is never counted" footnote.
- Words: coverage titles, ledger reasons, month labels and em dashes are fixed in all
  four languages.

## Priority issues

1. [P1] Family and Today disagree about what is waiting. Family's greeting counts every
   `pending` and `pending_validation` activity (own work, unapproved templates) and
   says "4 tasks are waiting for attention", with "Go to Today" under it; Today's Needs
   you counts only validations this user can give and says "You're all caught up". The
   hub sends the user to a screen that contradicts it. Fix: one shared count (the Needs
   you items) in both places, or name what is waiting ("2 of Ati's tasks wait for your
   validation"). Command: /impeccable clarify.
2. [P2] Me is the last screen in the old grammar. Gradient banner, nested
   Profile/Family/Wallet tabs, a dark hero balance card with "TOTAL BALANCE … COINS" in
   uppercase, "Activity Insights". Fix: one list with sections, balance as a plain row
   that opens the ledger, no gradient. Command: /impeccable distill.
3. [P2] Family's first screen spends its height on a greeting paragraph, a link, the
   onboarding checklist and a two-up member grid with coin balances. Balances side by
   side read as a scoreboard. Fix: Needs you summary first, members as one compact row,
   balances out of the hub (they live in Me and Stats). Command: /impeccable layout.
4. [P2] Casing and glyph drift. Title Case headings ("Active Family Members", "Tasks
   Completed", "New Activity", "Activity Insights") beside sentence case elsewhere;
   🔁 and 🪙 still mark recurrence and coins next to the new Material icons. Fix:
   sentence case everywhere; Icons.repeat_rounded and one coin icon. Command:
   /impeccable polish.

## Persona red flags

Casey (one-handed): validating is now Today → tap a block → Validate, all in the thumb
zone. But Family's "4 tasks waiting" sends Casey to Today, which shows nothing; Casey
concludes the app is wrong. Drag-to-move needs a long-press on a 15-minute block, which
is small; the sheet's Move is the reliable path.

Jordan (first-timer): the tour now teaches the real interaction (drag a task, tap an
hour). Still sees "cc", "Junior Explorer", "Coins from tasks" next to a 488 cc balance,
and a member grid that invites comparing balances.

Sam (screen reader): hours announce "Add at HH:00", blocks and chips carry hints, chart
summaries are read once. The 🔁 glyph in titles is read as "repeat button" or as an
emoji name depending on the voice.

## Minor observations

- Tasks: "New Activity" is a full-width tonal button above the filters; it is the
  least frequent action on that screen.
- Rewards: a single history row floats under a large empty state; fine, but the empty
  state could carry the history link instead.
- Today: the "You're all caught up" card costs a row on every visit; it could collapse
  to a line once dismissed for the day.
- Stats: "Tasks Completed" KPI beside "Coins from tasks": mixed case, and the KPI row
  repeats what the charts say.

## Questions to consider

- If Needs you is the definition of "waiting", should Family show it at all, or just link to it?
- Does Me need tabs, or is it one page with Profile, Family and Wallet as sections?
- Should balances be visible to everyone on the hub, or only in each person's wallet?
