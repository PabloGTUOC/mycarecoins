# Mobile UX Phase 1 — Implementation Brief

> **For a coding agent working without prior context.** This brief implements Phase 1
> ("Safety and access") of `docs/mobile-ux-proposal.md`. Read that proposal's §3 P0 items
> and §4 guardrails first, then `CLAUDE.md` for the repo rules. Scope is **Flutter only**:
> no backend, schema or API changes.

## Ground rules

- Work on a branch named `mobile-ux-phase1`, with **one commit per ticket**. Never commit to `main`.
- **Do not run `dart format` on whole files.** The code is not formatter-clean, and doing so
  turns a small change into a diff of hundreds of lines. Match the surrounding style by hand.
- Every new user-facing string goes in **all four** ARB files: `fluterFront/lib/l10n/app_{en,es,fr,de}.arb`.
  English is the template. Draft es/fr/de translations, and add the new keys to the PR
  description so a native speaker can review them. ICU plurals must not contain a bare `#`.
- Use the tokens in `lib/theme/app_theme.dart` and the widgets in `lib/widgets/ui.dart`
  (`Tappable`, `PillBadge`, `SegmentedTabs`, `EmptyState`). Don't introduce new raw `Color(0x…)` values.
- Don't change anything under `backend/`.
- Before every commit, from `fluterFront/`: `flutter analyze` (no issues) and `flutter test`
  (all pass; currently 59).

## T1 · Separate the day-change gesture from swipe-to-remove (P0-1)

**Where:** `lib/screens/daily_screen.dart`. In `_buildNarrow` (around line 1278) the whole
list is wrapped in a `GestureDetector` with `onHorizontalDragEnd` → `_changeDay`. Each card
is a `Dismissible` with `endToStart` (`_buildDismissibleCard`, around line 1384).

**Do:**
- Remove the horizontal-drag `GestureDetector` from the list body.
- Under the AppBar, add a week strip: seven day chips (weekday letter and date) for the week
  containing the selected day. Today gets a dot, the selected day a filled `primary` chip.
  Tapping a chip selects that day. A horizontal swipe **on the strip** moves a whole week.
  Each chip is at least 44×44 dp.
- Keep the AppBar ‹ › arrows and swipe-to-remove unchanged.

**Done when:** a left swipe on a card only ever offers removal; a swipe on the strip only
ever changes the week; there's a widget test that a horizontal drag on the list does not
change the date.

## T2 · Confirm before redeeming a reward (P0-2)

**Where:** `lib/screens/marketplace_screen.dart`. `_redeem` (around line 128) posts immediately.

**Do:** before posting, show a modal bottom sheet with the reward title, its cost, and the
balance after (current balance minus cost, from `AppState`), plus **Redeem** (primary) and
**Not now**. Post only on Redeem, and disable the button while the request runs.

**Done when:** tapping Redeem on a card never spends coins without the sheet; there's a
widget test that dismissing the sheet makes no API call.

## T3 · Readable pill and card colours (P0-3)

**Where:** `lib/theme/app_theme.dart`, `lib/screens/daily_screen.dart` (`_ActivityAction.pill`,
`_TimelineCard`), and any other `X` on `XSoft` text pairing (search for `warningSoft`,
`successSoft`, `primarySoft`, `dangerSoft`).

**Do:**
- Add `warningInk #92400E`, `successInk #166534`, `primaryInk #1D4ED8` and `dangerInk #B91C1C`.
- Wherever text or an icon sits on a `*Soft` fill, use the matching `*Ink` colour instead
  of the base one.
- Change the filled timeline card fills to `#15803D` (care) and `#B45309` (household); the
  white text stays.
- Add one line to `docs/DESIGN.md`: *soft fill → ink text, never the base colour*.

**Done when:** every pairing changed here is at least 4.5:1. Put the ratios in the commit
message; the proposal's §3 P0-3 table has them.

## T4 · Screen-reader labels (P0-4)

**Do:**
- `_TimelineCard` and the compact grid chip: wrap each in `Semantics` with one combined
  label: title, type name (not the emoji), time range, assignee, coin value, and status
  word. Exclude the emoji glyph from semantics (`ExcludeSemantics`).
- `_ActivityAction` pills that have an `onTap`: `Semantics(button: true, label: …)`.
- Bottom bar in `lib/screens/shell.dart` (around line 183): each item gets
  `Semantics(button: true, selected: i == _index, label: tabs[i].label)`.
- Add a `tooltip:` to the three `IconButton`s that lack one (search `IconButton(` in `lib/`).
- The label text needs new ARB keys (for example the type names, if none exist yet). Check
  for existing keys before adding any.

**Done when:** there's a widget test using `tester.getSemantics` / `matchesSemantics` that
asserts a card's label includes its title and status, and that the selected tab reports
`isSelected`.

## T5 · A 12 pt text floor (P1-5)

**Do:** raise every `fontSize` below 12 in `lib/` (62 sites; find them with
`grep -rnE "fontSize: ?(8|9|10|10\.5|11|11\.5)\b" lib`) to 12, starting with the
bottom-bar labels in `shell.dart`. Where 12 pt overflows a fixed-size container, make that
container flexible rather than shrinking the text. Leave the `textScaler` clamp in
`main.dart` alone; raising it is Phase 5.

**Done when:** that search returns nothing outside the landing page's illustrative phone
mockup (`_PhoneMockup` in `landing_screen.dart`), which is decorative and may stay small.
Any exception gets a comment.

## Hand back

Open a PR from `mobile-ux-phase1` to `main` that lists:
- each ticket and its commit;
- the new ARB keys;
- anything left undone, and why;
- screenshots of the Daily screen, the redeem sheet and a pill, on a 375-wide phone.
