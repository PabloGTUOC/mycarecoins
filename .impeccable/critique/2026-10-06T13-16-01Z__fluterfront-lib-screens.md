---
target: mobile app after Phase 1
total_score: 22
p0_count: 0
p1_count: 4
timestamp: 2026-10-06T13-16-01Z
slug: fluterfront-lib-screens
---
# Critique — CareCoins mobile app (after Phase 1)

Target: `fluterFront/lib/screens`, iPhone 17e simulator, production data, 2026-10-06.

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 2 | "5 tasks waiting" with no path to them; completion happens invisibly |
| 2 | Match system / real world | 2 | "Performance Analytics", "Income Generation Trend", "FAMILY ID 1", raw `monthly_distribution` |
| 3 | User control and freedom | 2 | Daily drops the tab bar; undo of a payout lives in Me → Wallet |
| 4 | Consistency and standards | 2 | Emoji vs icon glyphs; one-off purple gradient banner; tabs nested in 4 of 5 tabs |
| 5 | Error prevention | 3 | Redeem confirm and removal rules landed; catalogue trash on every row |
| 6 | Recognition rather than recall | 2 | Double-tap / long-press actions; work addressed to you not surfaced |
| 7 | Flexibility and efficiency | 2 | Core loop (validate, cover) is two levels deep |
| 8 | Aesthetic and minimalist design | 2 | ~35% of every first screen is chrome; 7 "Free day" rows; KPI grids |
| 9 | Error recovery | 2 | Toast-only errors outside the redeem sheet |
| 10 | Help and documentation | 3 | Help sheet, tour and checklist exist and are reachable |
| **Total** | | **22/40** | **Acceptable** |

## Anti-patterns verdict

LLM: not AI-slop in its bones (real product, real data, coherent tokens), but it carries
the generic-dashboard grammar PRODUCT.md rejects: hero-metric KPI grids on Family and
Stats, small all-caps tracked labels on every card, a gradient banner, corporate copy
("Performance Analytics", "Income Generation Trend"), emoji as structural icons.

Deterministic: the bundled detector reads HTML/CSS only. On `fluterFront/web` it found
1 issue (em-dash overuse, 5, `privacy.html`); it returns nothing for Dart. Code scans
from the Phase 1 audit stand in: 65 emoji glyphs in widget code, 57 raw colours.
Em dashes also appear in app copy (empty Rewards state, welcome dialog, "Oct 6 — 13").

## What's working

- The week strip on Daily (T1) reads instantly and is thumb-sized.
- The Add task sheet: search, Personal time as the first row, category filter.
- Empty states offer the next action (Rewards, Daily).
- Soft-fill ink colours (T3) now read clearly on pills and coin chips.

## Priority issues

1. [P1] The Family hub buries the work and misstates the numbers. It opens with a
   heading, a 3-card member grid and a week of seven rows that mostly say "Free day";
   the actionable items ("5 awaiting validation", the cover request) are 2-3 screens
   down or nowhere. The subtitle says the family "earned 968 cc today": 968 is the
   total balance (`dashEarned` is passed `totalCoins`). Fix: Needs-you block first
   (proposal P1-2), compress the week to busy days only, fix the copy.
2. [P1] Chrome eats the phone. A persistent pill header (logo + help + balance) plus a
   page title plus a two-line subtitle take ~35% of the first viewport on every tab;
   the New Activity form starts 60% down. Fix: drop the logo on phones, fold the title
   into the header, remove subtitles after first visit.
3. [P1] Navigation is two levels deep everywhere, and Daily leaves the shell.
   Activities, Rewards, Stats and Me each nest a 3-way segmented control; Daily is a
   pushed route without the tab bar. Fix: the D1 tab set (Today as a tab) and fewer
   nested tabs (Rewards Store/History in one list; Create as a button).
4. [P1] Language and data leaks. "Covering for …" is built in English on the server
   for every locale; the ledger shows `monthly_distribution`; Me shows the database
   "FAMILY ID 1"; chart axes print ISO months "2026-08".
5. [P2] Stats speaks corporate and hides fairness. "Performance Analytics", "Income
   Generation Trend", "Lifetime coins 24 cc" beside a 488 cc balance; the fairness
   block (personal time vs coverage) sits in the Members sub-tab though fairness is
   the product's principle 3.

## Persona red flags

Casey (distracted, one-handed): validating "5 awaiting" needs Family → scroll → a day
→ find the card → pill; the header actions sit at the top edge; Daily loses the bottom
bar so returning means a top-left back arrow.

Jordan (first-timer): sees "cc", "bounties", "Family ID", "Performance Analytics" on
day one; the welcome dialog promises a tour but the core loop (who validates what)
is never shown on the hub.

Sam (screen reader): T4 labelled cards and tabs; emoji glyphs remain in the catalogue,
the add-task sheet and the profile banner; KPI cards read label/value separately.

## Minor observations

- Catalogue: an "approved" pill on every row and a red trash on every row.
- Budget: a hero gauge for one number; "Scheduled/Used 0 cc" with a slash label.
- Me → Family: a red × overlapping a dependent's avatar.
- Daily (empty): "0 / 0 done" progress and two calls to action for one action.
- Recent activity lists "+0 cc" for personal time.

## Questions to consider

- What if the app opened on Today, and Family were the weekly review?
- Does a family of 2-6 people need a KPI grid at all, or one honest sentence?
- What would Stats say if it led with fairness instead of income?
