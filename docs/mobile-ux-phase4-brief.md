# Mobile UX Phase 4 — Implementation Brief

> **For a coding agent working without prior context.** Phase 4 follows the fourth design
> critique of 2026-10-09 (`.impeccable/critique/2026-10-09T10-20-00Z__fluterfront-lib-screens.md`,
> 30/40, one P1). Phase 3 (`docs/mobile-ux-phase3-brief.md`) brought Me and Family to the
> standard of Today; Phase 4 finishes Me's Family section, the wallet wording, Stats'
> Overview, and the leftovers the wider walk found. Same ground rules: one commit per
> ticket on the working branch, no whole-file `dart format`, every new string in all four
> ARB files, tokens from `lib/theme/app_theme.dart`, Material 3 components,
> `flutter analyze` and `flutter test` clean. **No `backend/` changes.**

> **Status (2026-10-10):** done on `mobile-ux-phase4` (not merged). Fifth critique: 32/40, no P0/P1
> (`.impeccable/critique/2026-10-10T00-20-00Z__fluterfront-lib-screens.md`).

## Decisions (2026-10-09)

1. Scope: all seven critique issues.
2. Tasks › Budget: **kept, rewritten as one line** (not removed).
3. Dependent badges ("Junior Explorer", "Furry Friend", "Guiding Star"): **kept**. Only the
   uppercase caregiver chip changes.
4. Stats: **tabs stay**; only Overview changes.

## P4-1 · Delete family is not a button (critique P1)

`profile_screen.dart` puts `VButton(type: VButtonType.danger)` "Delete family" full width
between the Family circle and "You".

- Replace it with a red text action ("Delete family", `TextButton` in the theme's error
  colour) as the last row inside the Family section, after the Family circle card — the
  same treatment P3-5 gave "Delete account". Caregivers only, as today.
- The existing `_deleteFamily` flow and its confirmation (unanimous approval) are
  unchanged.
- Tests: no `VButtonType.danger` on Me on phones; the Delete family action exists for a
  caregiver, not for a member, and opens the existing confirmation.

## P4-2 · A bounty is an offer, not a fine (critique P2)

The wallet shows `bounty_escrow` / `bounty_paid` as "You paid for not doing: {title}"
(`ledgerPaidNotDoing`, `profile_screen.dart` ~line 834).

- New wording, all four ARB files: "Offered for: {title}" with the untitled fallback
  "Bounty offered" (rename the key to `ledgerBountyOffered` / `ledgerBountyOfferedT`; do
  not keep the old key). Match the tone of `ledgerSweetenerEscrow` ("Offered for coverage").
- Check every other place the old key or wording appears (ledger sheet, stats) and use
  the new one.
- Tests: a `bounty_escrow` row renders "Offered for: Nap time".

## P4-3 · No emoji in strings (critique P2)

16 emoji live in `app_en.arb` values (and their translations): `welcomeTitle` 👋,
`toastRewardRedeemed` 🎉, `deletionBannerTitle` ⚠️, `typeChild` 👶, `typePet` 🐾,
`typeElderly` 👴, `inviteCaregiverBtn` ✉️, `generateLink` 🔗, `catCareEmoji` ❤️,
`catHouseholdEmoji` 🍽️, `legendRoles` 🟡🔵. Plus `Text('📷')` camera badges in
`profile_screen.dart` and `widgets/family_circle.dart`.

- Remove the emoji from the values in all four ARB files. Where the widget needs a
  visual, give it a Material icon (`Icons.mail_outline_rounded`, `Icons.link_rounded`,
  `Icons.photo_camera_rounded` with a Semantics label "Change photo", category icons as
  elsewhere, coloured dots as widgets for the legend).
- Leave the ✓ check glyphs alone (`pillValidate`, `pillDone`, `copied`, …): they are text
  glyphs that render correctly, not emoji.
- `landing_screen.dart` is a brand surface and is out of scope.
- Tests: extend the P3-3 scan test to the values of all four ARB files (emoji ranges
  only; ✓ allowed), and keep the widget-code scan.

## P4-4 · Stats Overview without a dashboard (critique P2)

On phones, Overview shows "Time given and taken", then a 2×2 grid of number cards
(`kpiLifetimeCoins` Coins from tasks, `kpiTasksCompleted`, Bounties offered, Rewards
claimed), a curved area line chart, a donut ("Category balance") and Task frequency.

- Phones: replace the 2×2 grid with one sentence, as Family did in P3-6 (e.g. "All time:
  27 cc earned from 14 tasks · 2 bounties offered · 1 reward claimed"). Wide layout keeps
  the cards.
- Every figure on Overview says its period. Find each figure's range in the stats data
  (`backend/src/services/` — read only) and label it ("All time", "This month",
  "Last 6 months"). The donut's "7 total" beside "14 tasks completed" must not read as a
  contradiction.
- Line charts in `widgets/charts.dart`: straight segments with point markers, no area
  gradient fill. With fewer than three points, show the values as text instead of a
  chart.
- Donut: when one category is 100 %, show the sentence ("All 7 tasks were care") instead
  of a one-colour ring.
- Members and Economy tabs unchanged.
- Tests: no KPI card grid on phones; the sentence renders; a two-point series renders as
  text; no `LinearGradient` fill in line charts.

## P4-5 · Caregiver chip in sentence case (critique P3, reduced)

Family circle on Me: the caregiver chip renders uppercase "CAREGIVER". Dependent badges
keep their names (decision 3).

- Chip text in sentence case ("Caregiver"); find where the uppercase comes from
  (`toUpperCase()` or a text style with caps) and remove it, without changing other
  chips that are meant to stay as they are.
- Tests: the chip reads "Caregiver".

## P4-6 · The add sheet is one list (critique P3)

Tapping an hour on Today opens "Add at HH:MM": each task is a separate bordered card,
while the Tasks catalogue is one divided list since P3-7.

- Render the sheet's task list as one divided list, reusing the P3-7 row widget or its
  styling (icon, title, "Care · 1 cc", trailing add icon). "Time for me" stays as its own
  highlighted row above the list.
- Tests: the sheet shows one list container, not a card per task.

## P4-7 · Task icons: paperwork and a neutral fallback (critique P3)

`lib/utils/task_icon.dart`: "Paperwork and bills" matches no rule and falls back to the
household icon, a fork and knife.

- Add a paperwork / bills / admin rule (`Icons.description_rounded` or
  `Icons.receipt_long_rounded`) with keywords in all four languages, like the other rules.
- The household fallback becomes neutral (`Icons.home_rounded`); the care fallback stays.
- Tests: "Paperwork and bills" (and its es/fr/de starter titles) gets the paperwork icon;
  an unknown household title gets the home icon.

## P4-8 · Budget as one line (critique minor, decision 2)

Tasks › Budget shows a card "Family budget health" containing a nested card with "Total
monthly pool", "Scheduled or used", "Estimated rate ~1 cc / hr" in warning orange.

The data (`GET /api/families/:id/budget`, `familyService.getFamilyBudget`) is: `monthlyBudget`,
`usedThisMonth` = coins of **completed** care tasks this month, `baseRatePerHour`. So
"Scheduled or used" is wrong: nothing scheduled is counted.

- Replace the card with one plain sentence block, no nested card, no orange:
  "This month: {used} of {pool} cc paid out for tasks. The rest is shared between
  caregivers at the end of the month." followed by a quiet second line
  "About {rate} cc per hour of care."
- Remove the keys that are no longer used from all four ARB files.
- Tests: Budget shows the sentence with the right numbers; no nested card.

## Order

P4-1 (the P1), P4-2, P4-3 (strings, touches many files, lands before layout work), P4-7,
P4-6, P4-5, P4-8, P4-4. Fifth critique after P4-4.

## Hand back per ticket

Files changed, new and removed ARB keys, `flutter analyze` and `flutter test` results,
and anything in the ticket that conflicted with existing behaviour (keep the existing
behaviour and say so; do not remove copy the ticket does not name).

## As built (2026-10-10)

Implemented by Antigravity from `.lead/` tickets, reviewed and committed by the lead, one
commit per ticket. `flutter analyze` clean, `flutter test` 274 passing.

| Ticket | Commit | Notes |
|---|---|---|
| P4-1 | `ff52a40` | Delete family is red `TextButton` text (`AppColors.danger`) |
| P4-2 | `e0a2e24` | `ledgerBountyOfferedT` "Offered for: {title}" / `ledgerBountyOffered` |
| P4-3 | `4936202` | 11 ARB values de-emoji'd; icons on invite/link/deletion banner; camera badges are icons labelled "Change photo"; ARB emoji scan test |
| P4-3b | `610d2f0` | Follow-up: personal-time glyphs (screen-reader only), feed, legends, reward card, push toast; lib scan allows only `landing_screen.dart` |
| P4-7 | `be599c4` | Paperwork rule → `receipt_long`; household fallback → `home` |
| P4-6 | `b16bfef` | Add-at-time sheet is one divided list |
| P4-5 | `9bfdb89` | Wider than briefed: the role chip was the raw API value uppercased, so it now uses `roleCaregiver`/`roleMember`; deletion statuses translated; absence labels lose ✈️ + uppercase; ⚠️ → icon; scan covers U+2600–27BF |
| P4-8 | `b84145b` | Budget is `budgetSentence` + bar + `budgetRateLine`; seven keys removed |
| P4-4 | `0701d47` | Phones: KPI sentence; "All time ·" subtitles; donut note and 100 % sentence; straight lines, no fill, < 3 points as text |
