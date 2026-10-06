# Mobile UX Proposal — Flutter app

> **Status: Phase 1 implemented (2026-10-06, branch `mobile-ux-phase1`); Phase 2 briefed in
> `docs/mobile-ux-phase2-brief.md`, reshaped by a design critique on the simulator (22/40).** A review of the phone experience in
> `fluterFront/` with a ranked list of changes. Each change names the evidence, the rule it
> rests on, and what it would take to build. Decisions D1–D4 (§6) are settled.
>
> Companion docs: `docs/PRODUCT.md` (principles cited as **P1–P5**), `docs/DESIGN.md`
> (tokens), `docs/onboarding-help-plan.md` (telemetry used in §7).

---

## 1. Method and limits

- **Rules:** the `ui-ux-pro-max` design skill's mobile guidelines (accessibility, touch,
  navigation, feedback, typography), checked against Apple HIG / Material where the skill
  cites them.
- **Design-system check:** the skill's recommendation for this product type (family
  coordination, warm, trusted) came back as *flat, touch-first, blue primary, amber accent,
  no shadows*. That is what `DESIGN.md` already specifies, so this proposal keeps the visual
  identity and works on interaction, structure and accessibility. **No rebrand.**
- **Evidence:** read from the code (`lib/`, 13.8k lines), with counts taken by search and
  contrast ratios computed from the real tokens. Line numbers are as of `main` on 2026-10-05.
- **Not done:** the app was not run on a device for this review. Every finding below is
  visible in the code, but on-device testing (§7) has to confirm the priority order before
  building.

---

## 2. What already works — keep it

- Pull-to-refresh on all six main screens, and a `LoadErrorState` with retry instead of a blank page.
- Empty states that offer an action (an empty day opens the task sheet).
- A floating **Add task** button on the Daily screen, within thumb reach.
- A five-item bottom bar with icon and label on every item (`shell.dart:104`).
- Safe areas respected on the shell, the bottom bar and sheets.
- Action pills already pad their tap area toward 44 dp without growing visually
  (`daily_screen.dart:1466`).
- Free-time gaps between activities say what they are for ("1h free · book time"), giving
  the hidden double-tap a visible place to live (`daily_screen.dart:1347`).
- Reduced motion is respected on the landing page and in the coach-mark tour.
- The setup wizard shows progress and blocks moving on with an invalid step.

---

## 3. Findings, ranked

**P0** = something wrong or unreachable today · **P1** = core-loop friction · **P2** = polish.

### P0-1 · Swiping left both changes the day and deletes a card

On phones the whole Daily list moves to the next day on a fast left swipe
(`daily_screen.dart:1280`, `onHorizontalDragEnd`). Every card in that same list is also a
`Dismissible` that removes the activity on a left swipe (`:1395`, `endToStart`). The same
gesture means "next day" or "delete" depending on where your finger lands and how fast it
moves. The confirm dialog prevents data loss, but the result is unpredictable at exactly the
moment the app is meant to be glanceable (P4).

*Rule:* `gesture-conflicts`, one primary gesture per region.

**Proposal.** Move day navigation onto the date header: a swipeable week strip of seven
day chips with today marked, keeping the arrows. Keep swipe-to-remove on cards. The list
body then only scrolls vertically.

### P0-2 · Redeeming a reward takes one tap, with no confirmation

`marketplace_screen.dart:128` posts the redemption the moment the button is pressed. Coins
leave the wallet atomically and there is no way back. Every other coin-moving action in the
app (delete series, delete family, delegate) asks first.

*Rule:* `confirmation-dialogs`, confirm irreversible spending.

**Proposal.** A bottom sheet: reward, cost, *balance after* ("You'll have 140 cc left"), and
**Redeem** / **Not now**. This is the only reward-side change rated P0.

### P0-3 · Action pills fail colour contrast

Computed from the real tokens. The pill text is 10.5–12 pt, so the 4.5:1 normal-text bar applies:

| Pill | Pair | Ratio | WCAG AA |
|---|---|---|---|
| Delegate / Awaiting / Offering | `warning` on `warningSoft` | **2.86** | fails |
| Take over | `success` on `successSoft` | **2.95** | fails |
| Validate | `primary` on `primarySoft` | 4.48 | just fails |
| Rejected | `danger` on `dangerSoft` | 4.10 | fails |
| Filled care card title | white on `success` | 3.30 | passes only as large bold text |
| Filled household card title | white on `warning` | 3.19 | passes only as large bold text |

*Rule:* `color-contrast` 4.5:1 for body text, and PRODUCT.md's own WCAG AA target.

**Proposal.** Add "ink" tokens for text on soft fills, and darken the filled-card fills:

| New token | Value | Ratio on its soft fill |
|---|---|---|
| `warningInk` | `#92400E` | 6.38 |
| `successInk` | `#166534` | 6.38 |
| `primaryInk` | `#1D4ED8` | 5.81 |
| `dangerInk` | `#B91C1C` | 5.50 |
| filled card fill (care / household) | `#15803D` / `#B45309` | white text 5.02 |

The hues stay the same; only the text gets darker. `DESIGN.md` gains a line: *soft fill →
ink text, never the base colour*.

### P0-4 · Screen readers get almost nothing

- **1** `Semantics` widget and **0** `semanticLabel`s across `lib/`.
- Activity type is shown only as an emoji glyph (`_activityEmoji`, `daily_screen.dart:1516`).
  TalkBack reads "red heart", "fork and knife with plate".
- The custom bottom bar is an `InkWell` row with no selected state (`shell.dart:185`), so
  VoiceOver can't tell which tab is current.
- 3 of 11 `IconButton`s have no tooltip, which is also their accessible name.

*Rules:* `voiceover-sr`, `aria-labels`, `nav-state-active`.

**Proposal.** Label each card as one unit: "Bath time, care, 18:00 to 18:30, Ana, worth 30
coins, awaiting validation". Give the action pill its own button label. Mark tabs with
`Semantics(selected:, button:)`. Add the three missing tooltips. That is about a dozen
widgets, not a rewrite.

### P1-1 · The signature screen isn't a tab

`PRODUCT.md` §4 calls the Daily schedule "the signature product view", but it isn't one
of the five tabs. It opens as a pushed route from the Family hub (`dashboard_screen.dart:269`,
reached from six different taps). On a phone, the screen used most in "brief, high-stress
moments" is always one level deep and loses its place when you switch tabs.

*Rules:* `bottom-nav-top-level`, P4 (mobile is the primary action surface).

**Proposal: tab set *Today · Family · Tasks · Rewards · Me*.**

```
 ┌────────────────────────────────────┐
 │  Today              Mon 6 Oct  ‹ › │
 │  ◦ Sa  ◦ Su  ● Mo  ◦ Tu  ◦ We  …   │ ← swipeable week strip (P0-1)
 │ ┌ Needs you ─────────────────────┐ │
 │ │ Validate “Bath time” · Ben  ›  │ │ ← finite list (P1-2)
 │ │ Ana asks you to cover Fri 18h ›│ │
 │ └────────────────────────────────┘ │
 │ 08:00  Breakfast prep     ✓ +20cc  │
 │ ─── 1h free · book time ───        │
 │ 18:00  Bath time   Ben  [Validate] │
 │                        (+ Add  ▾)  │ ← FAB: task / time for me (P1-4)
 ├────────────────────────────────────┤
 │ Today  Family  Tasks  Rewards  Me  │
 └────────────────────────────────────┘
```

- **Today** is the Daily screen as a tab, opening on today.
- **Family** is the current hub. Its KPI cards and "See stats" lead to Stats, which stops
  being a tab. Stats is review material and is used mostly on desktop (PRODUCT.md, Users).
- **Tasks** is the current Activities tab (catalogue / new / budget).
- On desktop the header keeps its links. Only the phone tab bar changes.

Keeping Stats as a tab and adding Today as a sixth would break the five-item limit, so
Stats moves under Family (decision **D1**).

### P1-2 · Things waiting on *you* are scattered and buried

The work a user must act on lives in four places. On the Family hub the order is: heading
→ checklist → members → pending approvals → week strip → **cover requests** (`:636`) →
offers → KPIs → feed. Validations appear only as pills on individual timeline cards. On a
phone, the most actionable item is several screens down, and nothing says when you're
finished.

*Rules:* `content-priority`, P1 (finite and completable).

**Proposal.** A **Needs you** block at the top of Today, holding only items addressed to the
current user: validations they can give, cover requests asked of them, member approvals
(caregivers only), and expiring offers they could take. Each row is one tap to act. When the
list is empty it collapses to a single line: *"You're all caught up."* That gives the app a
real end state, which P1 asks for.

### P1-3 · Completion is invisible, and so is undoing it

Users never mark a task done. The background sweep completes and pays every approved
activity once its end time passes (`backend/src/db/autoComplete.js`). Two things follow:

- The onboarding checklist tells new users to **"Mark it done"** (`checklistMarkDone`) and
  sends them to Daily, where no such action exists. They get stuck on step 3 of the core loop.
- If a task didn't actually happen, the only fix is **Profile → Wallet → Uncheck**
  (`profile_screen.dart:298`), three levels away from the card that is wrong.

*Rules:* `success-feedback`, `undo-support`, `error-recovery`.

**Proposal.**

- Before its end time, a card says when it will count: *"Counts at 18:30 · +30 cc"*.
- After the sweep, it shows *"Done · +30 cc"* with a quiet **Didn't happen?** link. The link
  runs the existing revert endpoint, which is now ledger-safe.
- The checklist step completes itself on the first payout (**D3**), with copy that
  describes what happens: *"Coins land when it ends"*.

### P1-4 · Key actions hide behind gestures nobody discovers

| Action | How it is reached today | Visible alternative |
|---|---|---|
| Book personal time | double-tap an hour (`:1039`), or tap a free gap | none if the day has no gaps |
| Make an activity repeat | long-press the card (`:1897`) | none |
| See why a completed card is locked | long-press | none |

*Rules:* `gesture-alternative`, `swipe-clarity`.

**Proposal.** The floating button opens a two-option sheet: **Add a task** / **Time for
me**. Each card gets a `⋯` button (48 dp) with *Repeat · Offer bounty · Remove · Details*.
Gestures stay as shortcuts; they are no longer the only way.

### P1-5 · Small text everywhere

62 places set text below 12 pt. The tab-bar labels are 10 pt (`shell.dart:198`) and the
compact pills 10.5 pt. On top of that, OS text scaling is capped at 1.3×
(`main.dart:83`), so people with large-text settings don't get them.

*Rules:* `readable-font-size`, `dynamic-type`.

**Proposal.** Set a 12 pt floor (tab labels go to 12). Then raise the cap to 2.0× one screen
at a time, testing each at 200%. The clamp's own comment says it waits for flexible
containers, so this belongs with the layout work in P1-1.

### P1-6 · Coin-moving forms only explain errors after you submit

Creating a reward with a missing field shows a toast (`errTitleCostRequired`), detached from
the field. The same pattern appears in the other create forms.

*Rules:* `error-placement`, `inline-validation`.

**Proposal.** Show the error under the field once it loses focus, keep the submit button
disabled until the form is valid, and focus the first invalid field.

### P2 · Polish

| # | Change | Evidence | Rule |
|---|---|---|---|
| 1 | Replace type emoji with icons from the Material Rounded set already in use, inside tinted circles. User-entered emoji stays. | about 65 emoji in widget code; 🧘 🏠 ❤️ 🍽️ as type glyphs | `no-emoji-icons`, `icon-style-consistent` |
| 2 | Skeletons for the first load of Today and Family | 9 full-screen spinners, 0 skeletons | `progressive-loading` |
| 3 | Light haptic on Validate, Accept cover and Redeem, and nowhere else | 0 haptic calls | `haptic-feedback` (sparingly) |
| 4 | Move the 57 raw `Color(0x…)` values in screens and widgets into tokens | prerequisite for dark mode | `color-semantic` |
| 5 | Dark theme, using the tokens from #4 | none today; the app is used at night | `dark-mode-pairing` |
| 6 | Deep links: a notification opens the exact day or request; an invite QR opens the app's join flow | `MOBILE_AUDIT.md` §4.4 still open | `deep-linking` |
| 7 | Stats on phones: a one-sentence summary card first ("This month Ana gave 32 h, took 4 h"), then the charts, each with a text alternative | 24 cards in three tabs | `data-density`, `screen-reader-summary` |
| 8 | Undo instead of confirm for removing a single, unpaid instance (series deletion keeps its confirm) | `confirmDismiss` dialog on every swipe | `undo-support` |

---

## 4. Guardrails from PRODUCT.md

These limit some of the proposals above. They are listed here so implementation doesn't
undo them:

- **No anxiety badges** (anti-references). The *Needs you* indicator is a quiet dot for
  items addressed to you (**D2**). Never a count, never for other people's activity.
- **Coins are not the point** (anti-references). "+30 cc" on a card is fine. Confetti,
  streaks and leaderboard language are not.
- **Declines stay invisible** (§15). *Needs you* lists cover requests, but a declined one
  just disappears. No "you declined 3" anywhere.
- **Colour is never the only signal** (Accessibility). Every pill and card state keeps its
  word or icon.

---

## 5. Roadmap

Each phase ships on its own. Effort is a rough estimate for one developer.

| Phase | Contents | Effort | Depends on |
|---|---|---|---|
| **1 — Safety and access** | P0-1 week strip and gesture split · P0-2 redeem sheet · P0-3 ink tokens · P0-4 semantics · P1-5 12 pt floor | 3–4 days | — |
| **2 — Today tab** | P1-1 tab restructure · P1-2 Needs you · P1-4 FAB sheet + card `⋯` menu | 4–6 days | D1, D2 |
| **3 — Completion clarity** | P1-3 card states + "Didn't happen?" · checklist step fix · P2-8 undo | 2–3 days | revert fix (shipped) |
| **4 — Polish** | P1-6 inline validation · P2-1 icons · P2-2 skeletons · P2-3 haptics · P2-7 stats summary | 3–4 days | — |
| **5 — Platform** | P2-4 tokens → P2-5 dark theme · P2-6 deep links · text-scale cap to 2.0× | 5–8 days | Phase 2 layouts |

Phase 1 has a self-contained implementation brief, written so a coding agent with no
prior context can do it: `docs/mobile-ux-phase1-brief.md`.

Every phase must keep `flutter analyze` and `flutter test` clean. Phases 1 and 2 add widget
tests: a semantics label on a card, the redeem sheet, and *Needs you* empty and filled.
New strings go into all four ARB files.

---

## 6. Decisions (settled 2026-10-05)

| | Question | Decision |
|---|---|---|
| **D1** | Tab set | **Today · Family · Tasks · Rewards · Me.** Stats is no longer a tab; it is reached from Family (KPI cards and a "See stats" link). Today is used daily, Stats monthly. |
| **D2** | A *Needs you* indicator on the Today tab | **A dot only:** never a count, only for items addressed to the current user, cleared when Today is viewed. |
| **D3** | The checklist's "complete" step | **Automatic:** it ticks on the first payout instead of asking the user to act. The copy describes what happens rather than an action. |
| **D4** | Dark mode timing | **After the token migration** (P2-4 → P2-5, Phase 5), so it is done once. |

---

## 7. How to tell it worked

The telemetry from `docs/onboarding-help-plan.md` (`onboarding_events`) already records
checklist steps:

- **Checklist step 3 completion rate** should rise once P1-3 lands. Today the step asks
  for an action that doesn't exist.
- **Time from first task to first validated task**, as defined in the onboarding plan's
  activation metric.
- **Uncheck usage moving from the Wallet to the card**, a sign people find the undo where
  the mistake is.

Before Phase 1, run a 20-minute hallway test on two real phones (one small, one with OS text
at its largest). Tasks: *find today's schedule · validate Ben's task · book the gym on Friday
· buy a reward*. Record where people hesitate, and re-rank §3 if the results disagree with it.
