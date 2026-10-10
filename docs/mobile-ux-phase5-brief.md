# Mobile UX Phase 5 — Implementation Brief

> **For a coding agent working without prior context.** Phase 5 follows the fifth design
> critique of 2026-10-10 (`.impeccable/critique/2026-10-10T00-20-00Z__fluterfront-lib-screens.md`,
> 32/40, no P0/P1). Phases 3–4 made Today, Family, Tasks, Rewards, Me and Stats › Overview
> calm; Phase 5 takes the dashboard grammar out of Stats › Members and Economy, makes every
> total say what it counts, and clears the small leftovers. Same ground rules: one commit
> per ticket on `mobile-ux-phase5`, no whole-file `dart format`, every new string in all
> four ARB files, tokens from `lib/theme/app_theme.dart`, Material 3 components,
> `flutter analyze` and `flutter test` clean. **One backend change** (P5-1); it reaches
> production only with the next deploy.

> **Status (2026-10-10):** in progress on `mobile-ux-phase5` (branched from the unmerged
> `mobile-ux-phase4`).

## Decisions (2026-10-10)

1. **Members: comparisons behind the chip.** Every Members card shows the family figure
   by default; per-person bars appear only with the "By caregiver" chip, as on Overview.
   No traffic-light or red colours for people.
2. **Economy is the developer's view, not the family's.** The Economy tab leaves the
   family app (release builds). Coin flow by reason and activity status stay visible in
   debug builds only. The two reward cards families do care about move to Members.
3. Target: about 36/40 (heuristics 1, 2, 4, 8 from 3 to 4). User control, error prevention
   and error recovery get a separate targeted review before any ticket.

## P5-1 · Completion counts only work that was due (backend)

`backend/src/routes/stats.js` `completionRates` counts every care activity that isn't
rejected — templates, tasks scheduled later today, and tasks waiting for someone else's
validation all sit in the denominator. Count only scheduled instances (`is_template =
false`) that have started (`starts_at <= NOW()`), and return `waiting`
(`pending_validation`) next to `total` and `completed`.

## P5-2 · Members: fair, not competitive (critique P2 #1, #2)

- "Coin balance leaderboard" → "Balances", no "Highest balance" summary, one neutral
  colour, no role legend.
- Completion rate: one sentence ("12 of 28 tasks done; 4 wait for someone to confirm"),
  no traffic-light legend or colours.
- Bounties: "Offered" no longer red.
- Each card: family figure by default, per-person bars behind the "By caregiver" chip.

## P5-3 · Economy leaves the family app (decision 2)

Release builds show two Stats tabs (Overview, Members); the wide layout drops the Economy
section. "Rewards by member" and "Top rewards" move to Members. Coin flow and status
distribution render only under `kDebugMode`, where "Bounties paid" becomes "Bounties
offered".

## P5-4 · Every total says what it counts (critique P2 #3)

Overview's sentence and Task frequency say covering shifts are included; Category balance
drops the subtitle that repeats its sentence when one category is 100 %.

## P5-5 · Family and Today leftovers (critique P3 #5, minor observations)

"TODAY" → "Today"; "your tasks wait for validation" names whose OK ("someone else in the
family"); no "Good morning" after midnight; a past day shows no "drag onto the day" tray.

## P5-6 · Card headers on phones (critique P3 #6)

On phones, a `VCard` action (the "By caregiver" chip) sits under the subtitle instead of
beside the title, so titles stay on one line.

## P5-7 · Colours from the theme (heuristic 4)

Raw `Color(0x…)` outside the theme: map each to an `AppColors` token (adding the few that
are missing), keep only the Google logo colours and shadow/scrim alphas, and enforce it
with a test.
