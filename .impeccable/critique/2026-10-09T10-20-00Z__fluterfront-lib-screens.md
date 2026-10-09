---
target: mobile app after Phase 3 second round
total_score: 30
p0_count: 0
p1_count: 1
timestamp: 2026-10-09T10-20-00Z
slug: fluterfront-lib-screens
---
# Critique — CareCoins mobile app (after Phase 3, second round)

Target: `fluterFront/lib/screens`, iPhone 17e simulator (iOS 27), production data
(read-only), 2026-10-09. Flutter 3.47.7, RevenueCat 10.15.2.
Previous: 2026-10-08 evening, 30/40.

This round walked more surface than the last: Stats (Overview), Tasks › Budget, the
add-at-time sheet and the full Family circle on Me were not in the previous critique.
The four issues from 2026-10-08 are fixed; the new ones come from the newly walked
screens, so the score holds rather than rises.

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | Family: "4 of your tasks wait for validation" still doesn't say whose OK |
| 2 | Match system / real world | 3 | "You paid for not doing: Nap time" for a bounty; "Family budget health"; "Junior Explorer" |
| 3 | User control and freedom | 3 | Undo, back, edit mode; unchanged |
| 4 | Consistency and standards | 3 | Tasks is one list, the add sheet is still a stack of cards; 16 emoji live in ARB strings |
| 5 | Error prevention | 2 | Delete family is a full-width solid red button in the middle of Me |
| 6 | Recognition rather than recall | 3 | Per-task icons help; household fallback is a fork and knife (Paperwork and bills) |
| 7 | Flexibility and efficiency | 3 | Tap-an-hour opens the add sheet with search and filters |
| 8 | Aesthetic and minimalist design | 3 | Me and Family are calm; Stats keeps a 2×2 KPI grid and a smoothed area chart |
| 9 | Error recovery | 3 | Unchanged |
| 10 | Help and documentation | 4 | Help row on Me, tour, "Saying no is never counted" stated where it matters |
| **Total** | | **30/40** | **Good** (unchanged; wider walk) |

## Anti-patterns verdict

LLM: Today, Family, Tasks and Me read as one product. The dashboard grammar now lives only
on Stats: a 2×2 grid of number cards (Coins from tasks, Tasks completed, Bounties offered,
Rewards claimed) under the "Time given and taken" card, and a curved area chart drawn
through two monthly points, which invents a smooth rise between August and September.
The donut under it is one solid colour ("Care 100%"), a chart with nothing to compare.

Deterministic: 40 emoji in Dart (21 on the landing page; was 48), 40 raw `Color(0x…)`
outside the theme (16 on the landing page; was 41). The P3-3 scan test covers widget code
only, so 16 emoji survive inside `app_en.arb` values (✉️ Invite caregiver, 🔗 Generate
link, 👶/🐾/👴 actor types, ❤️/🍽️ categories, 🟡🔵 legend, ⚠️ deletion banner, 🎉, 👋) and
two `Text('📷')` camera badges sit on avatars. On iOS the envelope renders as a grey blob.

## What's working

- Me's "You" section is fixed: Log out outlined, Delete account as red text last, no
  empty band. Wallet leads with "478 cc" and three plain lines.
- Family's numbers are one sentence; the week uses chevrons; members are a quiet list.
- Tasks is one divided list with a distinct icon per task; repeat marks only where they
  distinguish.
- Stats opens on "Time given and taken" with a plain sentence ("You covered 7 h 30 for
  Ati and took 6 h for yourself") and states "Saying no is never counted" under it.

## Priority issues

1. [P1] Me, Family section: **Delete family** is a full-width solid red button between
   the Family circle card and "You" — the loudest element on the page, under the thumb
   while scrolling, for the most destructive action in the app. P3-5 fixed exactly this
   for Log out. Fix: a red text action at the end of the Family circle card, behind the
   existing unanimous-approval confirmation. Command: /impeccable layout.
2. [P2] Ledger wording for a bounty: offering 10 cc on Nap time shows "You paid for not
   doing: Nap time −10 cc" at the top of the wallet. It reads as a fine and turns an
   offer into a confession — the opposite of what bounties and sweeteners are for.
   Coverage already says "Offered for coverage". Fix: "Offered for: Nap time" (and the
   untitled fallback "Bounty offered"). Command: /impeccable clarify.
3. [P2] Emoji in localized strings and avatar badges (list above). Fix: Material icons
   beside plain labels; extend the scan test to ARB values (landing page excepted).
   Command: /impeccable polish.
4. [P2] Stats, Overview: the 2×2 number grid is the hero-metric template; the line chart
   is curved with a gradient fill over two points; "Tasks completed 14" and the donut's
   "7 total" sit on one screen with no stated period, so they read as a contradiction.
   Fix: on phones, the numbers as one sentence (as Family); straight segments with point
   markers, no area fill; every figure says its period. Command: /impeccable distill.
5. [P3] Family circle badges: dependents are labelled "Junior Explorer", "Furry Friend",
   "Guiding Star"; the caregiver chip is uppercase "CAREGIVER". Gamified titles are an
   anti-reference (PRODUCT.md). Fix: plain roles (Child, Pet, Older adult, Caregiver) in
   sentence case, matching "Cared for" on the Family hub. Command: /impeccable clarify.
6. [P3] Add-at-time sheet (tap an hour on Today): each task is its own bordered card,
   while the Tasks catalogue is one divided list since P3-7. Fix: the same divided list.
   Command: /impeccable polish.
7. [P3] Task icons: titles with no rule fall back to a fork and knife for Household
   ("Paperwork and bills"). Fix: a paperwork/bills rule and a neutral household fallback
   (home). Command: /impeccable polish.

## Persona red flags

Casey (one-handed): scrolling Me past the Family circle puts Delete family, full width and
solid red, right where the thumb rests.

Jordan (first-timer): offers a bounty, then sees "You paid for not doing" in their
wallet and concludes bounties are a penalty. On Stats, 14 tasks and "7 total" disagree.

Sam (screen reader): "✉️ Invite caregiver" announces "envelope, Invite caregiver"; the 📷
badge announces "camera" with no action named.

## Minor observations

- Family: "4 of your tasks wait for validation" — say whose ("wait for Ati's OK"), or
  "wait for a caregiver's OK" when anyone may validate.
- Family › Coming up and Tasks › Budget nest a card inside a card.
- Tasks › Budget: "Family budget health · 0 of 720 cc scheduled this month · Estimated
  rate ~1 cc / hr" in warning orange, while a 2 cc task is scheduled today.
- Stats keeps "Economy" as a tab name; the line chart's x axis shows only two labels.
- "Account settings" is a second heading directly under "You".

## Questions to consider

- Does the Budget view belong on Tasks at all, now that the real ceiling is the monthly
  pot (`totalGdp`) and Stats › Economy exists?
- Should Stats on phones be one scrolling story (time given and taken, then work, then
  coins) rather than three tabs?
