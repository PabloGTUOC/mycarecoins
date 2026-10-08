---
target: mobile app after Phase 3
total_score: 30
p0_count: 0
p1_count: 0
timestamp: 2026-10-08T20-00-05Z
slug: fluterfront-lib-screens
---
# Critique — CareCoins mobile app (after Phase 3)

Target: `fluterFront/lib/screens`, iPhone 17e simulator, production data (read-only), 2026-10-08 evening.
Previous: 2026-10-08 morning, 29/40 (and 22/40 on 2026-10-06).

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | Family and Today now agree; the hub's "Tasks today · 4 awaiting validation" still doesn't say whose validation |
| 2 | Match system / real world | 3 | Sentence case and plain "Your balance 488 cc"; "Logout", "Coin economy", "bounties" remain |
| 3 | User control and freedom | 3 | Undo on schedule and move, back on Stats, edit mode for removals |
| 4 | Consistency and standards | 3 | Glyphs and casing fixed; « » text buttons on Family, two different button weights for the same rank on Me |
| 5 | Error prevention | 3 | Drag refusals and server-matched permissions; Delete account sits right beside Update profile at equal weight |
| 6 | Recognition rather than recall | 3 | Tray shows your habits first; all actions in the sheet are labelled |
| 7 | Flexibility and efficiency | 3 | Drag, tap-an-hour, habit-ranked tray, per-chart compare |
| 8 | Aesthetic and minimalist design | 3 | Me and Family lost the gradient, dark hero card and card grid; Family's KPI row and Me's account form remain heavy |
| 9 | Error recovery | 3 | Inline errors with Retry, localized messages |
| 10 | Help and documentation | 3 | Tour, help sheet, checklist; tour step moved onto the compare chip |
| **Total** | | **30/40** | **Good** (was 29) |

## Anti-patterns verdict

LLM: Today, Me, Family members and Stats no longer read as a template. The dashboard
grammar is down to one place: the second half of Family, a two-by-two KPI card grid
(Family balance, Tasks today, Open bounties, Recent activity) whose last card repeats the
"Recent activity" section directly below it. Me's "You" section is one long bordered card
holding a form, a notifications block, legal links, language, help and a full-width solid
red Logout: the loudest element on Me is signing out.

Deterministic: `detect.mjs` on `fluterFront/web` returns 0 findings (unchanged). It does
not read Dart. Code scans stand in: 48 emoji in widget code (was 63; 26 on the landing
page, a brand surface; the rest are mostly in the personal-time dialog, Family's agenda
and Stats legends), and 41 raw `Color(0x…)` outside the theme (was 51). No browser
overlay: a Flutter app on the iOS simulator has no DOM to inject into.

## What's working

- Me is one page that leads with what people open it for: "Your balance 488 cc", the last
  three wallet lines, "See family stats". No tabs to learn.
- Family's members are a quiet list in name order with role and balance; the hub no longer
  duplicates Today's Needs you, and its greeting only speaks up when something is waiting.
- The tray now reflects the person: their most-repeated tasks first, the catalogue one tap
  away. Stats puts each compare toggle on the chart it changes.

## Priority issues

1. [P2] Me, "You" section: the account form's two buttons put Delete account (outlined,
   red text) beside Update profile (filled, wrapping to two lines) at equal size; an empty
   band appears where the hidden subscription card sits between two dividers; Logout is a
   full-width solid red button, styled as the most dangerous thing on the page. Fix:
   Update profile as the one filled button, full width; Delete account moves to the end
   of the section as a red text action behind its existing confirmation; "Log out" as a
   plain row or outlined button; drop the divider pair when the subscription card hides.
   Command: /impeccable layout.
2. [P2] Family's lower half is still a KPI dashboard. Four equal cards, one of which
   ("Recent activity 3, completed recently") restates the section under it; "4 awaiting
   validation" leaves the reader guessing whose. Fix: on phones replace the grid with one
   sentence ("4 of your tasks wait for Ati's OK · 10 cc up for grabs") or drop it, and let
   Recent activity stand alone. Command: /impeccable distill.
3. [P2] Family's "Coming up" card: "+ Log time off" plus « and » text buttons as week
   pagination. The guillemets are glyphs, not icons, and have no visible label. Fix:
   chevron icons with tooltips; Log time off as a smaller text action (or into Today's
   "Time for me"). Command: /impeccable polish.
4. [P3] Tasks: every catalogue row carries the repeat icon because every template recurs,
   so the icon says nothing; each row is a separate card. Fix: show repeat only when it
   distinguishes (or in the sheet), and render the catalogue as one divided list like
   Members. Command: /impeccable quieter.

## Persona red flags

Casey (one-handed): Today is fully thumb-zone; the tray now starts with Casey's own
habits. On Me, Logout is the biggest red target under the thumb at the bottom of the page.

Jordan (first-timer): Family's KPI cards say "4 awaiting validation" without a who; Jordan
looks for the 4 on Today and finds "You're all caught up" (they are Jordan's own tasks,
waiting for someone else).

Sam (screen reader): repeat icons carry "Repeats", chips announce selection, chart
summaries read once. The « » pagination buttons read as the glyph names.

## Minor observations

- Family's identity: "Good evening, Papa! Nothing paid out yet today." is a nice line; it
  sits on a paragraph style larger than the section titles under it.
- "Logout" should be "Log out" (verb); "Coin economy" tab title on Stats is jargon.
- Rewards' single history row under an empty store is fine.
- Tray chips truncate the second title ("School or daycare dr…"): consider a max width
  with ellipsis rather than a hard cut at the screen edge.

## Questions to consider

- Does Family need numbers at all, or is the member list plus Recent activity enough?
- Should account editing live behind a row ("Your details") instead of an always-open form?
- Is Log time off a Family action or a Today action?
