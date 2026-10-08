---
name: CareCoins
description: Family caregiving coordination with a fair-share coin reward system.
colors:
  primary: "#2563EB"
  primary-soft: "#E8EFFE"
  primary-ink: "#1D4ED8"
  success: "#16A34A"
  success-soft: "#E7F6EC"
  success-ink: "#166534"
  success-strong: "#15803D"
  warning: "#D97706"
  warning-soft: "#FEF1E1"
  warning-ink: "#92400E"
  warning-strong: "#B45309"
  danger: "#DC2626"
  danger-soft: "#FCE8E8"
  danger-ink: "#B91C1C"
  bg: "#F7F8FA"
  surface: "#FFFFFF"
  border: "#E5E8EE"
  text-primary: "#0E1726"
  text-secondary: "#5B6478"
  input-bg: "#F1F5F9"
  input-border: "#CBD5E1"
typography:
  display:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "2.25rem"
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "1.2rem"
    fontWeight: 800
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "1rem"
    fontWeight: 500
    lineHeight: 1.6
  label:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 700
    lineHeight: 1
rounded:
  sm: "8px"
  md: "16px"
  lg: "24px"
  pill: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  2xl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#ffffff"
    rounded: "{rounded.pill}"
    padding: "0.6rem 1.2rem"
  button-primary-hover:
    backgroundColor: "{colors.primary}"
    textColor: "#ffffff"
  button-secondary:
    backgroundColor: "rgba(15,23,42,0.05)"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.pill}"
    padding: "0.6rem 1.2rem"
  button-danger:
    backgroundColor: "{colors.danger-soft}"
    textColor: "{colors.danger}"
    rounded: "{rounded.pill}"
    padding: "0.6rem 1.2rem"
  button-outline:
    backgroundColor: "transparent"
    textColor: "{colors.primary}"
    border: "1px solid {colors.primary}"
    rounded: "{rounded.pill}"
    padding: "0.6rem 1.2rem"
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    padding: "1.5rem"
  input:
    backgroundColor: "{colors.input-bg}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.pill}"
    padding: "0.6rem 0.8rem"
---

# Design System: CareCoins

## 1. Overview

**Creative North Star: "The Family Operations Room"**

CareCoins is the shared dashboard a family runs on. The design reflects that: structured enough to carry real information (who does what, who earned what, what's left), warm enough to feel like home. Warmth is earned through legibility and fair representation, not through decorative softness. Every surface should feel like it was designed by someone who respects the people using it in a busy morning.

Density is a virtue here. Families operate under time pressure. The UI packs information efficiently without feeling clinical. Single sans-serif family (Plus Jakarta Sans, 800 weight for all headings) creates visual unity; the bold weight carries hierarchy without needing multiple typefaces. Color is semantic and sparing: blue means "take action", green means "done", amber means "household", red means "alert or danger". Coins and contribution data are always legible at a glance.

This system explicitly rejects the social media aesthetic (no feeds, no engagement loops, no notification anxiety), cold corporate SaaS (no hero metrics, no navy-and-white enterprise chrome), and gamification theater (coins are a fairness tool, not a leaderboard sport).

**Key Characteristics:**
- Single typeface, full weight range — hierarchy through size + weight, never font-switching
- Semantic color only — blue for action, green for done, amber for household, red for danger
- Pill radius for interactive elements, 24px for containers, 8px for inline elements
- Flat-by-default elevation — shadows are responses to state, not decoration
- Mobile-first density — compact and purposeful; nothing wastes thumb-space

---

## 2. Colors: The Operations Palette

A restrained palette where each hue has one job. Primary blue drives every intentional action; semantic colors (green, amber, red) annotate status. Neutrals carry the load.

### Primary
- **Trusted Action Blue** (`#2563EB`): The single primary action color. Used on all primary buttons, active nav states, links, focus rings, and the FAB back button. Its presence signals "tap here, something happens." Used in soft form (`#E8EFFE`) as a background tint for selected states.

### Secondary
- **Task Done Green** (`#16A34A`): Marks completion. Completed activity chips, success toast backgrounds, the "+" add FAB, progress bar fill, care-category activity cards. Soft form (`#E7F6EC`) used for container backgrounds.
- **Household Amber** (`#D97706`): Marks household-category tasks. Household activity cards and completed chips. Soft form (`#FEF1E1`) for containers.

### Tertiary
- **Alert Red** (`#DC2626`): Danger states only: error toasts, rejected activity cards, the NOW timeline divider, absence banners, danger buttons. Never used decoratively. Soft form (`#FCE8E8`) for danger container backgrounds.

### Neutral
- **Deep Home Ink** (`#0E1726`): Primary text. All body copy, headings, button labels. Near-black with a slight navy cast.
- **Secondary Slate** (`#5B6478`): Secondary text, labels, captions, timestamps, placeholder context.
- **Cool Background** (`#F7F8FA`): App body background. Slightly cool-tinted off-white; not warm, not cream.
- **Surface White** (`#FFFFFF`): Card and panel surfaces. Sits above the background to create the first elevation layer without shadow.
- **Soft Border** (`#E5E8EE`): Dividers, card borders, input strokes at rest.
- **Input Fill** (`#F1F5F9`): Input field background. Slightly darker than the body bg to signal an editable zone.
- **Input Border** (`#CBD5E1`): Input stroke at rest; shifts to primary blue on focus.

**The One Job Rule.** Every color has one semantic role and stays in it. Blue is not used for decoration. Green is not used for branding. Amber is not used for warnings unrelated to household tasks. If a new color feels necessary, it is probably a state variation of an existing token, not a new hue.
**The Soft-Ink Rule.** Text on a soft fill uses that hue's ink token (`primary-ink`, `success-ink`, `warning-ink`, `danger-ink`), never the base colour, which fails contrast on its own soft tint. Solid fills carrying white text use the strong tokens (`success-strong`, `warning-strong`). In Flutter these live in the `CareColors` theme extension (`context.careColors`).

---

## 3. Typography

**Body/Display Font:** Plus Jakarta Sans (with system-ui, sans-serif fallback)

A single humanist geometric sans-serif used across all roles. Hierarchy is achieved entirely through weight (500 body, 700 labels, 800 headings) and scale. No second typeface is needed; the weight range is the system.

**Character:** High contrast between body (500) and headings (800) creates a strong visual pulse without multiple font families. The -0.02em letter-spacing on all headings tightens them into confident units; body copy runs at default tracking for readability.

### Hierarchy
- **Display** (800, 2.25rem, line-height 1.1, -0.02em): Page-level hero headings. Used sparingly — once per major surface.
- **Headline** (800, 1.5rem, line-height 1.2, -0.02em): Section headings, card titles, view names like "Daily Schedule".
- **Title** (800, 1.2rem, line-height 1.3, -0.02em): Sub-section labels, modal titles, VCard headings.
- **Body** (500, 1rem, line-height 1.6): All readable content. Cap line length at 65–75ch on prose surfaces.
- **Label** (700, 0.75rem, line-height 1): Chips, badges, timestamps, filter pills, status indicators. Never lowercase-only for status; always paired with a color or icon.

**Mobile scale:** h1 → 1.75rem, h2 → 1.25rem, h3 → 1rem on viewports ≤768px.

**The Weight-Or-Size Rule.** Never use a lighter weight to create hierarchy — use size. The 800-weight heading at a smaller size beats the 600-weight heading at a larger size for readability in a dense mobile UI. Italic is not part of the system.

---

## 4. Elevation

CareCoins uses **flat-by-default, ambient-on-state** elevation. Surfaces stack through background color (bg → surface → input-bg), not through shadows. Shadows appear only when an element needs to communicate lift: a floating FAB, an open modal, a hovered card.

### Shadow Vocabulary
- **Cards:** none. Elevation 0 with a `1px border` stroke (Material 3 outlined card).
- **Nav float** (`0 4px 24px rgba(14,23,38,0.06)`): the wide-layout pill header only. The phone `NavigationBar` is flat.
- **Modal** (`0 10px 30px rgba(14,23,38,0.12)`): Modals and sheets. Clear depth, not dramatic.
- **FAB** (`0 4px 20px rgba(0,0,0,0.25)`): Floating action buttons. Stronger shadow to communicate persistent floating position.
- **Focus ring** (`0 0 0 3px rgba(37,99,235,0.2)`): Input focus. Not a shadow — a 3px spread ring using primary blue at 20% opacity.

**The Flat-By-Default Rule.** A surface at rest has no shadow. A surface that responds (hover, focus, open) earns one. If you are adding a shadow to a static element that the user cannot interact with, remove it.

---

## 5. Components

**Material 3, brand kept** (decided 2026-10-07). Controls are stock Material 3 widgets, styled once in `buildAppTheme()` (`fluterFront/lib/theme/app_theme.dart`) from the tokens above: the CareCoins blue, Plus Jakarta Sans and the coin language stay; custom look-alike controls go. Cards are rounded containers (24px), never nested.

### Buttons
- **Shape:** full pill on every button. Minimum 44 × 44.
- **Filled** (`FilledButton`, primary bg, white text): the one most important action on a screen or sheet.
- **Tonal** (`FilledButton.tonal`, `primary-soft` bg, `primary-ink` text): supporting actions. The theme pins `secondaryContainer` to `primary-soft`; without that, M3 derives a lavender.
- **Outlined** (`OutlinedButton`, `primary` border and text): a second option of similar weight.
- **Danger** (filled with the error colour): destructive actions in sheets and dialogs only, after a confirmation.
- `VButton` remains as a wrapper that renders these.

### Segmented controls
`SegmentedButton`, single selection: selected segment `primary-soft` with `primary-ink` text (bold), others transparent with `text-secondary`. Used for Catalogue/Budget, Stats sections and the like.

### Chips / Pills
- **Status pill** (soft fill, ink text): states such as pending or away. Always with a word, never colour alone.
- **Coin pill** (`CoinBalancePill`): the user's balance in the top app bar; opens the wallet.
- **Task chips** in the Today tray: draggable, with a tap path to a time picker.

### Cards / Containers
- **Corner style:** 24px radius. **Background:** `surface` on `bg`. **Elevation:** 0, with a `1px` `border` stroke; no drop shadows.
- **KPI cards are quiet:** sentence-case labels in `text-secondary`, values in `text-primary`; colour only on a value that signals state.

### Inputs / Fields
- Pill radius, `input-bg` fill, `1px input-border`, 16px text. Focus shifts the border to `primary`.
- Time entry always uses `showTimePicker`; no hour/minute dropdowns.

### Navigation
- **Phones:** Material 3 `NavigationBar`, five destinations **Today · Family · Tasks · Rewards · Me**, labels always visible (12pt, bold when selected), selected indicator `primary-soft` with `primary-ink` icon. A small `Badge` dot (no number) on Today while *Needs you* has items. Each tab has a small top `AppBar`: title, help, coin pill. No logo on phones.
- **Wide layouts** (`isWideLayout`: width > 768 and shortest side ≥ 600): the pill header with nav links.

### Today: hour grid and task tray (signature component)
- **Hour grid** (6:00–24:00), the same component on phones and wide layouts. Activities are blocks sized by duration (title, assignee, coins), coloured by category with the soft/ink tokens; overlapping blocks (coverage) sit side by side. The red **NOW** line is scrolled into view; other days open an hour before their first activity. Past hours are muted. Absences are a shaded band ("Ati away"); pending personal-time requests are dashed outline blocks.
- **Needs you** sits above the grid, folded to one line on phones ("Validate Bath time, and 1 more"), never a count.
- **Task tray** (phones): a sheet peeking above the navigation bar with one row of task chips, most-scheduled first; swipe up or tap "All tasks" for search, category filter and Time for me. Long-press a chip to drag a ghost block onto the grid: it snaps to 15 minutes, shows its time range, turns error-coloured with the reason when the slot conflicts (busy, away, past) and refuses the drop. A drop schedules immediately, with a snack bar and Undo. Every drag has a tap path.
- Planned next (P2-9, P2-10): tap an empty hour to quick-add; tap a block for its actions sheet; long-press a block to move it; skeleton loading, empty and read-only past days.

### Sheets and dialogs
- Modal bottom sheets with a drag handle and 24px top corners are the default on phones (forms, confirmations such as redeeming a reward). Dialogs only for short confirmations.
- One primary action and one way out.

### Snack bars / Feedback
- Floating snack bars, 16px radius, bold white text. Actions that can be undone offer **Undo** in the snack bar instead of a confirmation dialog.
- Errors are localized (`app.errorTextFor`), never raw server text.

---

## 6. Views

### LandingView
Brand surface. Marketing copy, hero illustration, CTA to sign up. Only view where brand-register design applies — richer use of the primary blue, larger type scale, feature highlights. Does not share the app nav chrome.

### LoginView
Minimal. Email/password form + Google Sign-In button. No distraction. The single focus is authentication.

### OnboardingView
Step-by-step wizard for new users: create family → set up profile → add actors. Progress is shown with a simple step counter, not a progress bar (keeps it lightweight).

### JoinView
Handles both invite-link joins (UUID token in URL) and email-invitation acceptances. Single-action confirmation screen with family name prominently displayed.

### Family hub (`dashboard_screen.dart`)
Overview of the family's current state: the coins earned today, balances per member, quiet KPI cards that open Stats, the week with empty days collapsed into one line, recent completions. Designed for a 30-second check-in.

### Today (`daily_screen.dart`, signature view)
The first tab and the app's opening screen: *Needs you*, the week strip (tap a day, fling for another week), the hour grid and the task tray described in §5. Every design decision prioritises speed and glanceability. Personal time and absences are asked for from its header actions.

### Tasks (`activities_screen.dart`)
The task catalogue (templates) and the monthly budget, as two segments. New tasks are created in a sheet; caregivers approve proposed ones.

### Rewards (`marketplace_screen.dart`)
Store and redemption history in one list; creating a reward opens a sheet; redeeming asks for confirmation in a sheet showing the balance before and after.

### Stats (`stats_screen.dart`)
Not a tab; opened from the Family hub. Hand-rolled charts (`widgets/charts.dart`), including personal time taken vs. coverage given. Designed for planning sessions on desktop, scannable on mobile.

### Me (`profile_screen.dart`)
Three panels: AccountSettings (display name, avatar, alias, email), FamilyCircle (members, invitations, actors, invite links), WalletPanel (coin balance, ledger, login history). Tab navigation on mobile, sidebar layout on desktop.

---

## 7. PWA Design Considerations

- **Standalone mode:** the app runs without browser chrome. The nav bar is the only chrome. No browser back button — provide explicit back controls on every drilldown screen.
- **Install prompt:** shown after a meaningful interaction, not immediately on first visit.
- **Splash screen:** uses `background_color: #F7F8FA` and `theme_color: #2563EB` from the manifest — matches the app's visual identity without a custom splash asset.
- **Icon design:** a coin-mark icon at 192 × 192 and 512 × 512 (maskable variant included). The maskable version uses safe-zone padding so it adapts correctly to Android adaptive icon shapes.

---

## 8. Do's and Don'ts

### Do:
- **Do** use `primary` (#2563EB) exclusively for primary actions, active states, and focus rings. Its scarcity is its power.
- **Do** use full pill radius (9999px) on all buttons and inputs — it is the system's primary shape language.
- **Do** reach for the stock Material 3 widget and let `buildAppTheme()` style it, before building a custom control.
- **Do** use weight 800 for all headings, 700 for all labels and chips, 500 for body. Never go below 500 for any UI text.
- **Do** pair semantic colors with text or icons — green chip means "done", amber means "household". Never use color as the only signal.
- **Do** keep minimum touch targets at 44×44px on all interactive elements.
- **Do** show the NOW divider in `danger` (#DC2626) on the daily timeline. It is the single most spatially important element in the schedule view.
- **Do** give cards a `1px solid border` (#E5E8EE). Cards without borders disappear on the off-white background.
- **Do** use `text-wrap: balance` on headline and title elements to prevent awkward orphans.

### Don't:
- **Don't** introduce a notification-count badge, engagement metric, or "streak" visual. CareCoins is not a social product. Per PRODUCT.md: no Facebook/Instagram patterns, no engagement-bait UI.
- **Don't** use a second typeface. Plus Jakarta Sans at 500/700/800 is the complete typographic system.
- **Don't** use `opacity: 0.8` as a status signal on colored surfaces — it fails contrast. Use the `soft` token variants (e.g. `success-soft`) for muted states.
- **Don't** nest cards. A card inside a card is always wrong. Use a list row or a contained section with a border instead.
- **Don't** use shadows on static, non-interactive elements. Shadow = lift = the user expects to interact with it.
- **Don't** put base-colour text on its own soft tint (blue on `primary-soft`, green on `success-soft`). Use the ink token.
- **Don't** use `border-left` or `border-right` as a colored stripe accent. Use full background tints (`danger-soft`, `primary-soft`) instead.
- **Don't** use gradient text (`background-clip: text`). Color emphasis is weight + size, not gradient decoration.
- **Don't** build a leaderboard-first view. Coins are a fairness tool; the UI should communicate contribution and fairness, not competition rank.
- **Don't** use the cream/sand/warm-neutral band for backgrounds. The app bg is a cool-tinted off-white (#F7F8FA). Warmth is in the brand voice and the coin metaphor, not the background color.
- **Don't** use dark mode "because tools look dark." The physical scene is a bright kitchen or bedroom during a morning routine — light mode is the right answer for this product's context.
