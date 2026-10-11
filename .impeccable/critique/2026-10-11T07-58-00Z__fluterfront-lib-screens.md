---
target: mobile app after Phase 5
total_score: 34
p0_count: 0
p1_count: 0
timestamp: 2026-10-11T07-58-00Z
slug: fluterfront-lib-screens
---
# Critique — CareCoins mobile app (after Phase 5)

Target: `fluterFront/lib/screens`, iPhone 17e simulator (iOS 27), production data
(read-only), 2026-10-11. `main` at `4e8266d` (Phases 4 and 5 merged, not pushed).
Debug build, so Stats › Economy still shows; it is out of scope (release builds hide it).
Previous: 2026-10-10, reported 32/40. **That table actually sums to 31** (nine 3s and one
4); the comparison below is against 31.

The backend half of P5-1 is not deployed, so Members › Tasks done still shows the old
denominator ("15 of 31", "Papa 12 of 28") and no "waiting" clause.

All six issues from 2026-10-10 are fixed (P5-2…P5-6), and P5-7 removed the raw colours.

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 4 | "4 of your tasks wait for someone else to confirm them"; no "Good morning" after midnight |
| 2 | Match system / real world | 4 | "Balances", "Bounties offered"; "15 of 31 tasks that were due are done" reads stiffly |
| 3 | User control and freedom | 3 | Unchanged: removing a one-off task has no Undo |
| 4 | Consistency and standards | 4 | Every total names its scope; colours from the theme, enforced by a test |
| 5 | Error prevention | 3 | Unchanged |
| 6 | Recognition rather than recall | 3 | Task names truncated in the catalogue ("School or daycare drop-…") |
| 7 | Flexibility and efficiency | 3 | Unchanged |
| 8 | Aesthetic and minimalist design | 3 | Members is calm but is four identical cards, each holding one sentence |
| 9 | Error recovery | 3 | Unchanged: English-only server errors, 5 s toasts with no retry |
| 10 | Help and documentation | 4 | "All time" / "Right now" on every card; notes say what each chart counts |
| **Total** | | **34/40** | **Good** (+3 on a corrected 31) |

## Anti-patterns verdict

LLM: the competitive grammar is gone. No leaderboard, no traffic lights, no red on people;
comparisons wait behind "By caregiver". What remains is template repetition: Stats ›
Members is four cards with the same shape (28 px title, period, chip, one sentence), which
is a lot of chrome for four sentences, and "Most popular rewards" is a single full-width
bar for one reward claimed once.

Deterministic: raw opaque `Color(0xFF…)` outside the theme and landing page: 5, all the
Google logo (was 25), enforced by `theme_colours_p5_7_test.dart`. Emoji and ARB glyph
checks still at 0.

## What's working

- Family: "Good morning, Papa! Nothing paid out yet today."; the day tile reads "Today";
  the waiting line says whose OK it needs.
- Stats › Overview: one totals sentence that says covering shifts and former members are
  included; Category balance and Task frequency each carry a note on what they count, and
  the three figures (15, 13, 8) no longer contradict one another.
- Stats card headers fit on one line on a phone, with the chip underneath.
- Me: wallet, family and account settings read in order; destructive actions are quiet
  red text at the end of their sections.

## Priority issues

1. [P2] Server errors are English-only (carried from the Phase 5 lead review). A Spanish,
   French or German user sees backend text verbatim. Fix: stable error codes, mapped to
   ARB keys, English as the fallback. Command: /impeccable clarify. (Heuristic 9.)
2. [P2] No Undo for removing a one-off task, and error toasts vanish after 5 s with no
   retry; a failed Undo is swallowed. Scheduling and moving already offer Undo; removing
   should too. Command: /impeccable harden. (Heuristics 3, 5, 9.)
3. [P2] Stats › Members: four identical cards for four sentences. Fix: one "This family"
   card with the four sentences as a short list, and one "By caregiver" chip that expands
   all four comparisons; hide "Most popular rewards" until at least two rewards have been
   claimed. Command: /impeccable distill. (Heuristic 8.)
4. [P3] Members › Tasks done, with the chip: "Ati 3 of 3" above "Papa 12 of 28" still
   reads as a ranking, and until P5-1 is deployed Papa's 28 includes work that was not
   due. Deploy first; then consider showing each person's done count only, without "of N".
   Command: /impeccable clarify.
5. [P3] "15 of 31 tasks that were due are done." Fix: "15 of 31 due tasks done." or "Done:
   15 of the 31 tasks that were due." Command: /impeccable clarify.
6. [P3] Tasks › Catalogue truncates names ("Dishes and kitchen clean…", "School or
   daycare drop-…") because the repeat icon sits on the title line. Fix: let the title
   wrap to two lines, or move the repeat icon into the subtitle. Command: /impeccable
   layout. (Heuristic 6.)

## Persona red flags

Jordan (first-timer, Spanish): a validation error appears in English for five seconds,
then disappears, with no way to try again.

Riley (stressed caregiver): removes a task from today by mistake; there is no Undo, and
they have to find it in the catalogue and drag it back.

## Minor observations

- Members › Bounties: "15 cc offered, 10 cc earned by whoever took them, 0 cc returned"
  leaves 5 cc unaccounted for (still open). Say "5 cc still open".
- Rewards › History and the wallet show spending as red "-500 cc" / "-10 cc". A reward
  claim is not a loss; consider ink for negatives and keep red for errors.
- "Most popular rewards" shows the reward name in lower case as typed ("balancing out").
  User data; fine, but it looks like a bug in a chart.
- Overview "Time given and taken": the light-blue figure "7 h 30" on white is the
  lowest-contrast text on the screen.

## Questions to consider

- Should Phase 6 start with the error codes (biggest gap, touches backend and app) or with
  the Members consolidation (small, visible)?
- Does the per-caregiver Tasks done view need "of N" at all, given the product goal is
  "visible and fair, not competitive"?
