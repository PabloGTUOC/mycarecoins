---
target: mobile app after Phase 4
total_score: 32
p0_count: 0
p1_count: 0
timestamp: 2026-10-10T00-20-00Z
slug: fluterfront-lib-screens
---
# Critique — CareCoins mobile app (after Phase 4)

Target: `fluterFront/lib/screens`, iPhone 17e simulator (iOS 27), production data
(read-only), 2026-10-10. Branch `mobile-ux-phase4` at `0701d47`.
Previous: 2026-10-09, 30/40.

All seven issues from 2026-10-09 are fixed (P4-1…P4-8, plus P4-3b). This round also
walked Stats › Members and Stats › Economy in full for the first time; most new
findings come from there.

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | Family: "4 of your tasks wait for validation" still doesn't say whose OK |
| 2 | Match system / real world | 3 | "Coin balance leaderboard"; Economy legend still says "Bounties paid" |
| 3 | User control and freedom | 3 | Unchanged |
| 4 | Consistency and standards | 3 | Four different task totals across Stats (15, 8, 49, "1269 cc" vs a 574 axis) |
| 5 | Error prevention | 3 | Delete family is now quiet red text (was 2) |
| 6 | Recognition rather than recall | 3 | Paperwork has its own icon; household fallback is a house |
| 7 | Flexibility and efficiency | 3 | Add sheet is one searchable list |
| 8 | Aesthetic and minimalist design | 3 | Overview is calm; Members/Economy keep the dashboard grammar |
| 9 | Error recovery | 3 | Unchanged |
| 10 | Help and documentation | 4 | "All time" on every Overview card; donut says what it counts |
| **Total** | | **32/40** | **Good** (+2) |

## Anti-patterns verdict

LLM: Today, Family, Tasks, Rewards, Me and Stats › Overview now read as one calm product.
The dashboard grammar has retreated to Stats › Members and Economy: a "leaderboard", a
traffic-light completion rate that paints a caregiver red at 43 %, bounties "offered" in
red, and a stacked bar where one 574 cc reward redemption flattens every other month.

Deterministic: emoji in Dart outside the landing page 0 (was 19); ARB values 0 (was 16);
both enforced by `words_and_glyphs_test.dart`. Raw `Color(0x…)` outside the theme and
landing page: 25 (unchanged; mostly avatar badge tints in `family_circle.dart`).

## What's working

- Me: wallet leads with "490 cc", ledger lines read "Offered for: Nap time"; Delete
  family is red text at the end of the section; the role chip says "Caregiver".
- Tasks › Budget is two sentences and a bar.
- Stats › Overview: one sentence for the totals, "All time ·" on every card, straight
  line with point markers, "All 8 tasks were care." instead of a one-colour donut, and a
  note saying what the donut counts.
- The add-at-time sheet and the Tasks catalogue are the same divided list.

## Priority issues

1. [P2] Stats › Members, Completion rate: a traffic-light legend (≥80 % green, 50–79 %
   orange, <50 % red) paints Papa's bar red at "43 % (12/28)". The denominator counts
   tasks still waiting for someone else's validation and tasks scheduled later today, so
   the caregiver doing most of the work looks like the one failing. Shame colours are an
   anti-reference (PRODUCT.md: visible, fair, not competitive). Fix: one neutral colour,
   count only tasks whose time has passed, and say it in words ("12 of 28 done; 4 wait
   for validation"). Command: /impeccable clarify.
2. [P2] Stats › Members: "Coin balance leaderboard" ranks caregivers by balance, and the
   Bounties card shows "Offered 15 cc" in red. Balance isn't merit (it falls when you
   redeem a reward); offering a bounty isn't a loss. Fix: "Balances" without ranking
   language, and offered in a neutral colour. Command: /impeccable clarify.
3. [P2] Stats, four totals that don't agree: Overview "15 completed tasks", the donut "8
   tasks", Economy "Activity status distribution 49 total · 31 % completed", and "Coin
   flow · Most active month: September (1269 cc)" over an axis that tops out at 574.
   Each is defensible, none says what it counts. Fix: every figure names its scope
   ("care tasks", "all activities including personal time", "coins in and out"), the
   same way the donut now does. Command: /impeccable clarify.
4. [P3] Economy legend still says "Bounties paid" (`flowBountiesPaid`), the wording P4-2
   removed from the wallet. Fix: "Bounties offered". Command: /impeccable clarify.
5. [P3] Family › Coming up: the current day's tile reads "TODAY" from the ARB value
   `dayToday` itself, the last all-caps label after P4-5. Fix: "Today". Command:
   /impeccable polish.
6. [P3] Stats card headers on a phone: the title and the "By caregiver" chip share one
   row, so "Coins earned per / month" and "Category / balance" wrap to two lines at
   28 px. Fix: the chip under the subtitle on phones, or a smaller card title.
   Command: /impeccable layout.

## Persona red flags

Jordan (first-timer): opens Members, sees their own name in red at 43 % under a
leaderboard and reads it as "you are the problem", while they have done 12 of the
family's 15 tasks.

Riley (stressed caregiver): on Economy, one reward redemption is a tall orange bar; the
months they actually worked are a sliver at the bottom.

## Minor observations

- Family: "4 of your tasks wait for validation" — whose OK? (carried over).
- Today, past day: "This day has passed" sits above a "Tasks · drag onto the day" tray.
- Family greets "Good morning" just after midnight.
- Stats › Overview: the Category balance subtitle "Most work in Care: 100 %" repeats the
  sentence below it; Task frequency counts covering shifts while the donut note above it
  says they are not counted.

## Questions to consider

- Should Members and Economy keep per-caregiver comparisons at all, or move behind the
  "By caregiver" chip the way Overview's charts do?
- Is Stats › Economy for families, or for the developer? Coin flow by reason reads like
  an operator's dashboard.
