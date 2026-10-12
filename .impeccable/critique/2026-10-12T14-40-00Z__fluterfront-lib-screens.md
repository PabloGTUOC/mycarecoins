---
target: mobile app after Phase 6
total_score: 37
p0_count: 0
p1_count: 0
timestamp: 2026-10-12T14-40-00Z
slug: fluterfront-lib-screens
---
# Critique — CareCoins mobile app (after Phase 6)

Target: `fluterFront/lib/screens`, iPhone 17e simulator (iOS 27), production data
(read-only), 2026-10-12. Branch `mobile-ux-phase6` at `62eba26` (not merged). Debug
build, so Stats › Economy still shows; it is out of scope (release builds hide it).
Previous: 2026-10-11, 34/40.

The backend is not deployed: P5-1 (Tasks done still reads "15 of 31") and P6-4/P6-5
(error codes) are not live, so server errors still arrive in English. The translated
errors, the Retry toast and the removal Undo are verified by tests (Flutter 315,
backend 233), not on the device: removing a task on production data was avoided.

Of the six issues from 2026-10-11: #1, #2, #3, #5 and #6 are fixed (P6-1…P6-7); #4
("of N" per person) is fixed, and the family total waits for the deploy.

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 4 | "4 of your tasks wait for someone else to confirm them"; "Today" on the day tile |
| 2 | Match system / real world | 4 | "15 of 31 due tasks done."; "5 cc still open"; but "returned" in the sentence, "Refunded" in the breakdown |
| 3 | User control and freedom | 4 | Removing, scheduling and moving a task all offer Undo, and every Undo snackbar now closes by itself |
| 4 | Consistency and standards | 4 | One card shape on Members; "This family · All time" above a "Right now" sentence |
| 5 | Error prevention | 3 | Unchanged |
| 6 | Recognition rather than recall | 3 | Catalogue names wrap; the Today tray still cuts "School or daycare dro…" |
| 7 | Flexibility and efficiency | 3 | Unchanged |
| 8 | Aesthetic and minimalist design | 4 | Members is one calm card; the breakdown still draws three empty bars for a person with no bounties |
| 9 | Error recovery | 4 | 10 s errors with close and Retry; 5xx in the user's language; 122 server codes in four languages (needs the deploy) |
| 10 | Help and documentation | 4 | Notes on every chart; "A balance goes down when someone claims a reward, so it is not a score." |
| **Total** | | **37/40** | **Excellent** (+3, on target) |

## Anti-patterns verdict

LLM: no template repetition left on Members: four sentences in one card, comparisons
behind one chip. The per-person view has two levels (16 px section, 13 px grey name).
What reads as generated is now only in the edges: a full bar row for every zero, and a
repeat icon that wraps onto its own line.

Deterministic: opaque raw `Color(0xFF…)` outside the theme and landing page: 5, all the
Google logo (unchanged; translucent shadow colours are not counted). Emoji: 0. The five
"✓" glyphs in ARB strings (`pillValidate`, `pillDone`, `copied`, …) are unchanged since
Phase 3. `flutter analyze` clean.

## What's working

- Stats › Members: "Right now 2 people hold 973 cc between them. / 15 of 31 due tasks
  done. / Bounties: … 5 cc still open. / Most claimed reward: …". One card, one chip.
- Per-person "Tasks done" says "3 done", "12 done": no denominator, no ranking.
- "Time given and taken": the values beside the bars are ink, readable on white.
- Tasks › Catalogue: "Dishes and kitchen cleanup" shows in full.
- Errors: a dropped connection or a server failure stays 10 s, can be closed, and offers
  "Try again"; a failed deferred delete brings the task back with an error.

## Priority issues

1. [P2] Deploy the backend. Until then Spanish, French and German users still see English
   server errors, and Members still says "15 of 31". Every Phase 6 gain on heuristic 9
   is invisible in production. Run `scripts/deploy.sh --dry-run` first.
2. [P3] Members mixes periods: the card says "All time" and its first sentence says
   "Right now". Fix: drop the subtitle (each sentence carries its own period) or move
   balances out of the "All time" card. Command: /impeccable clarify. (Heuristic 4.)
3. [P3] One thing, two words: the family sentence says "0 cc returned", the breakdown says
   "Refunded". Pick "returned" (it matches the wallet's "Coverage offer returned").
   Command: /impeccable clarify. (Heuristic 2.)
4. [P3] Per-person Bounties draws three empty bars for Ati (0 / 0 / 0). Fix: one line,
   "Ati: no bounties yet", or skip people with nothing. Command: /impeccable distill.
   (Heuristic 8.)
5. [P3] Catalogue: when a title wraps, the repeat icon can land alone on the second line
   ("Dishes and kitchen cleanup" / ↻). Fix: join it to the last word (a word joiner
   before the span) or move it into the subtitle. Command: /impeccable layout.
6. [P3] Today's task tray truncates chip names ("School or daycare dro…"). Fix: a max
   width with ellipsis at a word boundary, or two lines. Command: /impeccable layout.
   (Heuristic 6.)

## Persona red flags

Jordan (first-timer, Spanish): after the deploy, none. Today, server validation errors are
still English (now for 10 s, with a close button).

Riley (stressed caregiver): removes a task by mistake and taps Undo. Covered, but only by
tests so far; try it once on a test family after the deploy.

## Minor observations

- Rewards › History and the wallet still show spending as red "-500 cc" / "-10 cc".
  Carried from the last critique.
- Category balance says "All 8 tasks were care" (covering excluded), Task frequency
  counts covering shifts (5× at the top). Both notes say so, but the 8 vs 13 still invites
  the question.
- The "Done" pill uses `Colors.black26` as its fill, outside the tokens.

## Questions to consider

- Deploy before Phase 7, so the next critique can score heuristic 9 on the device?
- Heuristics 5, 6 and 7 have sat at 3 for three critiques. Is a phase on error
  prevention (conflicts before they happen) and power use (repeat yesterday, bulk
  schedule) worth it, or is 37 the place to stop polishing?
