# Palette analysis against Wada's Dictionary of Colour Combinations (2026-10-23)

Source: `mattdesl/dictionary-of-colour-combinations` `colors.json` (159 colours, 348
combinations). Distance is CIEDE2000; under ~5 reads as the same colour, over 10 as a
different one. Contrast is WCAG 2.

## Nearest Wada colour per token (before)

| Token | Value | Nearest | ΔE |
|---|---|---|---|
| danger | `#DC2626` | Spectrum Red `#E31F26` | 1.2 |
| badgeElderly | `#F59E0B` | Yellow Orange `#F99D1B` | 1.9 |
| gold | `#FBBF24` | Orange Yellow `#FCB315` | 4.2 |
| successInk | `#166534` | Diamine Green `#1A7444` | 5.2 |
| warning | `#D97706` | Raw Sienna `#BB7125` | 6.6 |
| success | `#16A34A` | Green `#489B6E` | 8.8 |
| primary | `#2563EB` | Blue `#006EB8` | 9.6 |
| accentSecondary | `#60A5FA` | Salvia Blue `#97ACC8` | 11.1 |
| primaryInk | `#1D4ED8` | Deep Lyons Blue `#1C4286` | 11.4 |
| indigo | `#6366F1` | Olympic Blue `#5A82B3` | 11.8 |
| violet | `#8B5CF6` | Blue Violet `#6450A1` | 14.7 |

The warm side already sat on Wada pigments; the blues and violets were Tailwind screen hues
with no pigment analogue, and carried the "cold SaaS" read PRODUCT.md rejects. The core set
(blue, teal-green, yellow orange, cream) is Wada combination 267.

## Defects found

- Family circle badges: base colour text on a 12 % tint of itself, 1.96–3.85:1 (AA 4.5).
- Purple-to-blue gradient (avatar fallback, profile accents).
- Caregiver chart series and member cards used success/warning/danger/violet as identity
  colours, breaking the One Job Rule (a person drawn in "done" green or "alert" red).
- Coin pill used household amber, white initials on `#D97706` at 3.19:1.

## Decisions (owner: "do 1 to 5 all of them")

1. Badges: soft fill + ink text per person colour (≥ 5.9:1).
2. Gradient and indigo/violet removed; flat blue.
3. People colours: Blue `#006EB8`, Benzol Green `#00978D`, Yellow Orange `#F99D1B`, Aconite
   Violet `#A36AA5` (combinations 267, 257), each with soft and ink.
4. Primary `#2563EB` → `#006EB8` (white 5.35:1); ink `#005B8D` (7.29:1); soft `#E6F0F8`.
5. Coin tokens: `#F99D1B` mark, `#FEE9CA` fill, `#7C4226` text (6.65:1).

Kept: neutrals (DESIGN.md rejects cream grounds), success green (teal is too close to the
blue to also mean done), danger (already Spectrum Red). `adminFront/` keeps the old blue.
