# Mobile UX Phase 2 — Device test checklist

What the automated tests and the read-only simulator checks could not cover: real
gestures, and anything that writes. Run it on a phone (or the simulator with a mouse) on
branch `mobile-ux-phase1`, ideally in a test family. Everything that writes here writes
to whatever server the build points at.

Run: `cd fluterFront && flutter run --dart-define=API_BASE=<server> --dart-define=PURCHASES_ENABLED=false`

## Today: adding

- [ ] Drag a chip from the tray onto a future hour: a ghost follows with the snapped time
      (15 minutes); release schedules it with no dialog; the SnackBar says "<task> at
      HH:MM" with Undo; Undo removes it.
- [ ] Drag over the past, over your time off, or over something you already have: the
      ghost shows the refusal and the drop does nothing.
- [ ] Drag towards the top or bottom edge: the grid scrolls.
- [ ] Tap an empty future slot: "Add at HH:MM" (snapped down to the quarter hour); one tap
      on a task schedules it; "Time for me" opens personal time at that time.
- [ ] Double-tap an empty slot: personal time opens directly.
- [ ] Tap a tray chip: the time picker opens; picking a time schedules it.

## Today: changing

- [ ] Tap a block: the sheet shows title, time, who, coins and only the actions you may
      take. Check one of yours, one of someone else's, a personal time and a coverage
      shift (coverage shows no actions, only "Ends with the personal time it covers").
- [ ] Move (sheet): the time picker, then the block moves; Undo moves it back.
- [ ] Long-press a block you may move and drag it: same ghost and refusals as the tray;
      release moves it; Undo moves it back. Try a short (15-minute) block too.
- [ ] Remove (sheet): the same confirmations as before; for a recurring task the
      single/series choice; for your covered personal time the coverage warning.
- [ ] Repeat appears only on recurring tasks and opens the recurrence dialog.
- [ ] Validate (sheet or the pill on the block) for someone else's finished task.
- [ ] Take over on someone else's task with a bounty.

## Today: states

- [ ] Kill the network and open Today fresh: the error sits inside the grid with Retry.
      With data loaded, pull to refresh offline: the grid stays and a SnackBar appears.
- [ ] Open a past day: "This day has passed" under the week strip; no adding, dragging
      or moving; blocks still open the sheet; Validate still works.
- [ ] An empty future day: one line, "Nothing planned. Drag a task here, or tap an hour."
- [ ] First launch after clearing the app's data: the tour points at the tray handle,
      then at an hour.
- [ ] VoiceOver: hours read "Add at HH:00" and add when activated; blocks and chips read
      their hints.

## Elsewhere

- [ ] Family → Stats: Stats opens with a back button; the compare switch works.
- [ ] Stats: the fairness card first, its sentence, the month label and the footnote.
- [ ] Wallet: every line has a readable label (no raw codes), including a monthly share
      and a reward redemption, in Spanish too.
- [ ] Me → Family: the × on dependents appears only after Edit.
- [ ] Tasks: the ⋮ menu deletes a template after the confirmation; only pending or
      rejected templates show a pill.
- [ ] Switch the phone to Spanish, French and German once: Today, the sheet, Stats and
      the wallet read naturally, with no English left and no em dashes.

## Known, not regressions

- Production still runs the old backend: until the branch is deployed, it lets a member
  delete someone else's personal time and put coverage up for a bounty.
