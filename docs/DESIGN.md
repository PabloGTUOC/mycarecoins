---
name: CareCoins
description: Family caregiving coordination with a fair-share coin reward system.
colors:
  primary: "#2563EB"
  primary-soft: "#E8EFFE"
  success: "#16A34A"
  success-soft: "#E7F6EC"
  warning: "#D97706"
  warning-soft: "#FEF1E1"
  danger: "#DC2626"
  danger-soft: "#FCE8E8"
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
*soft fill → ink text, never the base colour.*

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
- **Ambient card** (`0 10px 25px -5px rgba(0,0,0,0.05)`): Default card lift. Barely perceptible — marks a panel as interactive without competing for attention.
- **Nav float** (`0 4px 24px rgba(14,23,38,0.06)`): Pill navigation. Slight float to indicate the nav is above the content plane.
- **Modal** (`0 10px 30px rgba(14,23,38,0.12)`): Modals and sheets. Clear depth, not dramatic.
- **FAB** (`0 4px 20px rgba(0,0,0,0.25)`): Floating action buttons. Stronger shadow to communicate persistent floating position.
- **Focus ring** (`0 0 0 3px rgba(37,99,235,0.2)`): Input focus. Not a shadow — a 3px spread ring using primary blue at 20% opacity.

**The Flat-By-Default Rule.** A surface at rest has no shadow. A surface that responds (hover, focus, open) earns one. If you are adding a shadow to a static element that the user cannot interact with, remove it.

---

## 5. Components

Components are compact and purposeful. Buttons are pill-shaped and confident. Cards are rounded containers (24px), never nested. Inputs are pill-shaped to match button language and use a filled background to signal editability.

### Buttons
- **Shape:** Full pill (9999px radius) for primary, secondary, and danger. No sharp-corner buttons anywhere in the system.
- **Primary** (`#2563EB` bg, white text, `0.6rem 1.2rem` padding, `min-height 44px`): The single most important action on the screen. Blue glow shadow (`0 4px 14px rgba(37,99,235,0.3)`) reinforces its weight. One per view or modal.
- **Hover:** `filter: brightness(1.1)` + deeper glow. No background color shift.
- **Active:** `scale(0.97)` micro-press.
- **Secondary** (translucent dark fill `rgba(15,23,42,0.05)`, `text-primary`, `1px border input-border`): Supporting actions. Cancel, close, back.
- **Outline** (transparent bg, `primary` text, `1px border primary`): Secondary call-to-action that needs more visual weight than `secondary` but without a filled background. Used alongside primary actions where two options share similar prominence.
- **Danger** (`danger-soft` bg, `danger` text, `1px border danger-soft`): Destructive actions in modals only. Never used as a primary page action.
- **Disabled:** `opacity: 0.6`, `cursor: not-allowed`. No other visual change.

### Chips / Pills
- **Filter chip** (active: `primary` bg, white text; inactive: `surface` bg, `text-secondary`, `1px border`): Category filters, tag selectors. Full pill radius.
- **Status chip** (`success`/`warning` bg, white text): Completed activity labels in the done bar. Small, scannable.
- **Coin chip** (`bg` fill, `border`, `primary` coin value): Coin counters in the nav and profile. Pill shape with avatar + amount + unit.

### Cards / Containers
- **Corner style:** 24px radius (`--r-lg`). Generous, household-feeling.
- **Background:** `surface` (`#FFFFFF`) on `bg` (`#F7F8FA`). The 1-step tone difference creates hierarchy without shadow.
- **Shadow:** Ambient card shadow at rest. No hover shadow shift (cards are not primary interactables).
- **Border:** `1px solid border` (`#E5E8EE`). Always present on cards; removes ambiguity about where the card ends.
- **Internal padding:** 1.5rem. Consistent across all VCard uses.

### Inputs / Fields
- **Style:** Pill radius (matching buttons), `input-bg` fill (`#F1F5F9`), `1px border input-border` (`#CBD5E1`), 16px font-size (prevents iOS Safari zoom).
- **Focus:** Border shifts to `primary` blue; `0 0 0 3px rgba(37,99,235,0.2)` focus ring; background shifts to pure white.
- **Placeholder:** `rgba(148,163,184,0.5)` — intentionally faint; the field must be visibly empty before the user types.
- **Disabled:** `opacity: 0.6`, `cursor: not-allowed`.

### Navigation
- **Desktop:** Floating pill container, `rgba(255,255,255,0.85)` backdrop with `blur(12px)`. Nav links are pill-shaped; active state uses `primary-soft` background + `primary` text. Sticky at top.
- **Mobile:** Fixed bottom tab bar, 5 items, `rgba(255,255,255,0.92)` backdrop with `blur(12px)`. Active tab uses `primary` text color only — no background pill on mobile tab. Font 10px, weight 700.
- **Logo mark:** 32px square, `primary` bg, 8px radius (`--r-sm`), white icon.

### Daily Timeline (Signature Component)
The mobile condensed timeline list is the primary product surface on mobile. Each row pairs a 52px time-label column (right-aligned, `text-secondary`, 0.72rem) with a full-width card. Activity cards use the assignee color from `MEMBER_THEMES` — saturated solids (blue, green, orange, red), white text, 16px radius. The NOW divider is a red horizontal rule with "NOW" label in `danger` color. Gap indicators ("1h 30min free") appear between cards when gaps exceed 30 minutes, aligned to the card column.

### Modals
- Full-screen overlay on mobile (`position: fixed, inset: 0`).
- Centered sheet on desktop with `max-width: 480px`.
- `backdrop-filter: blur(4px)` on overlay background.
- One primary action and one secondary (cancel/close). Danger actions use `button-danger`.

### Toast / Feedback
- Success: `success-soft` background, `success` text.
- Error: `danger-soft` background, `danger` text.
- Auto-dismiss: 3.5 s success, 5 s error.
- Position: top-center on mobile, top-right on desktop.

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

### DashboardView
Overview of the family's current state. Coin balances per member, activity summary KPIs, recent completions. Dense but scannable — designed for a 30-second check-in.

### DailyView (signature view)
Vertical timeline for a specific date. Scrollable, time-labelled rows. Day navigation via swipe or header arrows. This is the primary daily-use screen — every design decision prioritises speed and glanceability. Bottom sheets and dialogs (`lib/widgets/`, e.g. `personal_time_dialog.dart`, `absence_dialog.dart`) handle scheduling, completing, personal time and bounty actions inline without leaving the screen.

### ActivitiesView
Kanban-style board with status columns. Caregivers approve and schedule from here. Members mark activities done. Filter chips allow narrowing by category or status.

### MarketplaceView
Grid of reward cards. Cost shown prominently in the primary coin chip. Redemption history below the grid shows social proof (who redeemed what recently).

### StatsView
Chart-heavy. ECharts for bar and line charts. Monthly toggle for time navigation. Designed for planning sessions on desktop, scannable on mobile.

### ProfileView
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
- **Don't** use `border-left` or `border-right` as a colored stripe accent. Use full background tints (`danger-soft`, `primary-soft`) instead.
- **Don't** use gradient text (`background-clip: text`). Color emphasis is weight + size, not gradient decoration.
- **Don't** build a leaderboard-first view. Coins are a fairness tool; the UI should communicate contribution and fairness, not competition rank.
- **Don't** use the cream/sand/warm-neutral band for backgrounds. The app bg is a cool-tinted off-white (#F7F8FA). Warmth is in the brand voice and the coin metaphor, not the background color.
- **Don't** use dark mode "because tools look dark." The physical scene is a bright kitchen or bedroom during a morning routine — light mode is the right answer for this product's context.
