# Flutter Frontend — Technical Reference

The CareCoins frontend is a **single Flutter codebase** (`fluterFront/`) shipping to **web,
iOS and Android**. It talks to the Node/Express backend over REST with Firebase ID tokens,
and to nothing else.

---

## Table of Contents

1. [Tech Stack](#1-tech-stack)
2. [Project Structure](#2-project-structure)
3. [Bootstrap and the Auth Gate](#3-bootstrap-and-the-auth-gate)
4. [State Management](#4-state-management)
5. [Navigation Shell](#5-navigation-shell)
6. [Screens](#6-screens)
7. [Design System and Widgets](#7-design-system-and-widgets)
8. [API Communication](#8-api-communication)
9. [Localization](#9-localization)
10. [Push Notifications](#10-push-notifications)
11. [Purchases](#11-purchases)
12. [Onboarding, Tours and Telemetry](#12-onboarding-tours-and-telemetry)
13. [Build and Run](#13-build-and-run)
14. [Testing](#14-testing)
15. [Platform Notes and Gotchas](#15-platform-notes-and-gotchas)

---

## 1. Tech Stack

| Dependency | Version | Role |
|---|---|---|
| Flutter / Dart | stable channel | UI framework, one codebase for web + iOS + Android |
| `provider` | `^6.1.2` | State management — a single `ChangeNotifier` |
| `http` | `^1.2.2` | REST client underneath `ApiClient` |
| `intl` | `>=0.19 <0.21` | Date and number formatting, locale-aware |
| `flutter_localizations` + `gen-l10n` | SDK | Localization; ARB files compiled at build time |
| `google_fonts` | `^6.2.1` | Plus Jakarta Sans |
| `firebase_core` / `firebase_auth` | `^3.8` / `^5.3.3` | Identity |
| `google_sign_in` | `^6.2.2` | Google authentication |
| `firebase_messaging` | `^15.2.10` | Push notifications |
| `shared_preferences` | `^2.3.0` | Device-local flags (locale, tour state) |
| `purchases_flutter` / `purchases_ui_flutter` | `^9.0.0` | RevenueCat SDK and prebuilt paywall |
| `image_picker` | `^1.2.3` | Avatar upload (gallery only — see §15) |
| `qr_flutter` | `^4.1.0` | QR codes for invite links |
| `url_launcher` | `^6.3.1` | Opens the hosted privacy policy and terms |

There is **no** router package, no code generation, and no local database. Navigation is an
`IndexedStack` in the shell; all persistent state lives on the server.

---

## 2. Project Structure

```
fluterFront/lib/
├── main.dart                     # Firebase init, MaterialApp, locale wiring, auth gate
├── firebase_options.dart         # Generated; web/iOS/Android Firebase config compiled in
│
├── state/
│   └── app_state.dart            # The single ChangeNotifier (auth, /api/me, family, toasts)
│
├── services/
│   ├── api_client.dart           # REST: JSON in/out, Bearer token, timeout, ApiException
│   ├── push_service.dart         # FCM token lifecycle + foreground messages
│   ├── purchase_service.dart     # RevenueCat: configure, identity, paywall, restore
│   ├── tour_service.dart         # Which coach-mark tours have been seen
│   └── telemetry.dart            # Onboarding events → POST /api/events
│
├── screens/
│   ├── shell.dart                # Tab scaffold: pill nav (wide) / bottom bar (narrow)
│   ├── landing_screen.dart       # Signed-out brand surface
│   ├── login_screen.dart         # Email/password + Google
│   ├── onboarding_screen.dart    # Create-family wizard / join by link
│   ├── dashboard_screen.dart     # Family hub
│   ├── daily_screen.dart         # The daily timeline — the signature screen
│   ├── activities_screen.dart    # Template library and creation
│   ├── marketplace_screen.dart   # Rewards store
│   ├── stats_screen.dart         # Charts
│   ├── profile_screen.dart       # Account, prefs, wallet, family circle, subscription
│   └── admin_screen.dart         # Platform admin console
│
├── widgets/
│   ├── ui.dart                   # The design-system kit (VCard, VButton, VInput, …)
│   ├── charts.dart               # Hand-rolled charts — no charting dependency
│   ├── personal_time_dialog.dart # Ask for personal time
│   ├── absence_dialog.dart       # Log time off (≥ 24 h)
│   ├── family_circle.dart        # Dependents, invitations, QR
│   ├── subscription_card.dart    # MyCareCoins Pro
│   ├── help_sheet.dart           # Help + glossary
│   ├── coach_marks.dart          # Spotlight tour overlay
│   └── activation_checklist.dart # First-run checklist on the dashboard
│
├── data/starter_packs.dart       # Localized starter-task catalogue
├── theme/app_theme.dart          # Colour, radius and typography tokens
├── utils/                        # json.dart (toNum etc.), avatar_upload.dart,
│                                 # legal_links.dart (privacy + terms)
└── l10n/app_{en,es,fr,de}.arb    # 787 keys × 4 languages
```

`lib/l10n/app_localizations*.dart` is **generated** by `flutter gen-l10n` and gitignored —
never edit it, edit the ARB files.

---

## 3. Bootstrap and the Auth Gate

`main.dart` does four things, in order:

1. `Firebase.initializeApp` with `firebase_options.dart`. When
   `--dart-define=AUTH_EMULATOR=host:port` is set it then calls `useAuthEmulator`, which is
   how the whole stack can run locally with no real accounts.
2. Reads the saved locale from `SharedPreferences` **before** the first frame and seeds it
   into `AppState`, so the app never renders in the device language and then visibly snaps to
   the chosen one.
3. Builds `MaterialApp` inside a `Selector` that watches **only** `AppState.locale` —
   unrelated notifications (toasts, profile refreshes) must not rebuild the whole app or its
   theme.
4. Renders `_ToastListener(child: _AuthGate())`.

The auth gate is the routing model: there is no route table and no guards. It renders the
landing/login screens, the onboarding wizard, or the `Shell`, based on
`authReady` / `firebaseAvailable` / `hasFamilies`. A user without a family cannot reach the
tabs at all, which is why no screen has to handle an empty family.

---

## 4. State Management

One `ChangeNotifier`: `AppState` (~345 lines). It owns

- **Session** — `authReady`, `firebaseAvailable`, `login`/`register`/`logout`, the Firebase
  ID-token listener, and `loginEventId` for session audit.
- **The `/api/me` payload** — `profile`, `families`, `actors`, `pendingRequests`, refreshed by
  `fetchUserData()` after every mutation that could change them.
- **Derived getters** — `family`, `familyId`, `hasFamilies`, `isCaregiver`,
  `isPlatformAdmin`. Screens read these rather than digging into the raw maps.
- **Locale** — `locale`, `seedLocale`, `setLocale` (persisted).
- **Toasts** — `success` / `error` strings plus `runAction()`, which wraps an async call,
  clears messages, shows a success toast on success and a localized error on failure. Almost
  every mutating call in the app goes through it.

Everything else is `StatefulWidget` local state. There is deliberately no second store: screen
data is fetched by the screen that shows it and thrown away with it.

---

## 5. Navigation Shell

`shell.dart` holds five tabs — Family, Activities, Rewards, Stats, Me — in an `IndexedStack`,
so tab state survives switching. It is responsive on one breakpoint,
`kMobileBreakpoint = 768.0` (`theme/app_theme.dart`): a pill header with nav links above it,
a bottom navigation bar below it. `isTablet` additionally requires `shortestSide >= 600`, which
is what separates a large phone from a real tablet layout.

Because `IndexedStack` keeps every tab alive, screens are told when they become visible again
(an `active` flag) so they can refetch silently — without that, tabs go stale behind your back.

---

## 6. Screens

| Screen | What it is |
|---|---|
| `landing_screen.dart` | Acquisition surface for signed-out visitors; the one **brand** register in the app |
| `login_screen.dart` | Email/password and Google, with autofill and forgot-password |
| `onboarding_screen.dart` | Paged create-family wizard (caretakers, dependents, activity-areas questionnaire, starter-task preview) and join-by-token |
| `dashboard_screen.dart` | Family hub: member grid, KPIs, week strip, bounties, absences, activation checklist, pending personal-time requests |
| `daily_screen.dart` | The signature screen. Hour grid with drag-and-drop on wide layouts, a timeline list with day-swipe on phones, NOW divider, free-time gaps, bounties, personal-time chips |
| `activities_screen.dart` | Template catalogue, creation with a budget-bounded coin slider, budget gauge |
| `marketplace_screen.dart` | Rewards: store, history, creation |
| `stats_screen.dart` | Charts, including personal time taken vs. coverage given |
| `profile_screen.dart` | Account settings, avatar, notification preferences, language, wallet + ledger, family circle, subscription, admin entry |
| `admin_screen.dart` | Platform registry, plan catalogue, billing and grants — gated on `isPlatformAdmin` |

---

## 7. Design System and Widgets

`theme/app_theme.dart` holds the tokens; `docs/DESIGN.md` explains the intent. Every colour
has exactly one semantic job:

| Token | Value | Job |
|---|---|---|
| `primary` | `#2563EB` | Action |
| `success` | `#16A34A` | Done |
| `warning` | `#D97706` | Household / caution |
| `danger` | `#DC2626` | Destructive |
| `bg` / `surface` / `border` | `#F7F8FA` / `#FFFFFF` / `#E5E8EE` | Ground, cards, edges |
| `textPrimary` / `textSecondary` | `#0E1726` / `#5B6478` | Hierarchy by weight and size, not colour |

Each has a `…Soft` companion for backgrounds. `widgets/ui.dart` is the kit: `VCard`,
`VButton`, `VInput`, `KpiCard`, `PillBadge`, `SegmentedTabs`, `Tappable`, `EmptyState`,
`LoadErrorState`, `PageHeading`, `AvatarCircle`, `AssigneeBadge`. Build screens from these
rather than raw Material widgets, or the app drifts.

Charts in `widgets/charts.dart` are hand-rolled `CustomPainter`s — a deliberate choice to
avoid a charting dependency for what is a handful of bar and stacked-bar forms.

---

## 8. API Communication

`ApiClient` (`services/api_client.dart`) is small on purpose:

- JSON in and out; `Authorization: Bearer <Firebase ID token>` on every call.
- A **20-second timeout** per request.
- Failures become a typed `ApiException` with an `ApiErrorKind` — `timeout`, `network`,
  `server`, `requestFailed` — carrying the backend's `data.error` string when there is one.
  The kind is turned into user-facing text at the display boundary, so error copy stays
  localized rather than being baked into the client.
- Base URL comes from `--dart-define=API_BASE`, defaulting to `http://localhost:3000`.

`AppState.runAction()` is the standard call site: it handles the toast, the error mapping and
the refresh, so screens rarely touch `ApiClient` directly for mutations.

---

## 9. Localization

English, Spanish, French and German — **783 keys per language**, in
`lib/l10n/app_{en,es,fr,de}.arb`, compiled by `flutter gen-l10n` (configured in `l10n.yaml`,
run automatically on `pub get` and build).

Rules that matter:

- `app_en.arb` is the template and the only file carrying `@key` metadata (descriptions,
  placeholders). Translations hold keys and values only.
- **`untranslated.json` must be empty** before a release — it is regenerated on every
  build and is the CI gate against a half-translated language.
- `AppLocalizations.of(context)` is non-null (`nullable-getter: false`); locales are fully
  resolved.
- Dates and numbers go through `intl` with the active locale — never hand-formatted.

Full workflow and guardrails: `docs/i18n-plan.md`.

---

## 10. Push Notifications

`services/push_service.dart` owns the FCM token lifecycle: register on enable, silently
refresh on startup, remove on disable, plus foreground message handling. Tokens live server-side
in `fcm_tokens` (multi-device), and per-category opt-outs in `notification_preferences`.

On web, background delivery needs `web/firebase-messaging-sw.js`; the VAPID key is a
compile-time constant overridable with `--dart-define=FIREBASE_VAPID_KEY=…`.

**Local testing caveat:** with the Firebase Auth emulator active, the *backend* cannot send
push at all unless `GOOGLE_APPLICATION_CREDENTIALS` is also exported — and the failure is
silent. See `docs/personal-time-plan.md` (Phase 5) for the full explanation.

---

## 11. Purchases

`services/purchase_service.dart` wraps RevenueCat and **no-ops on web**
(`supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid)`), so the same code runs
everywhere.

- `syncIdentity(backendUserId)` ties the RevenueCat identity to our user id; called after
  `/api/me` resolves and safe to repeat.
- The paywall is RevenueCat's prebuilt UI (`purchases_ui_flutter`).
- `restorePurchases()` exists because Apple requires a restore entry point. Entitlements are
  authoritative **on the backend**, so restore is really a re-sync.
- Entitlement id: `MyCareCoins Pro`.

> **Release requirement.** The SDK keys default to RevenueCat's **test store** key. Store
> builds must pass real keys:
> `--dart-define=RC_IOS_KEY=appl_… --dart-define=RC_ANDROID_KEY=goog_…`
> A release built without them will look fine and sell nothing.

---

### Legal documents

`utils/legal_links.dart` holds the two hosted URLs and the `LegalLinks` block that renders
them in Personal Area, directly beneath the subscription card. Both stores require a reachable
privacy policy, and Apple requires the policy **and** the terms of use to be reachable inside
the app when it sells auto-renewable subscriptions (Guideline 3.1.2).

The pages themselves are plain HTML in `web/`, so the Flutter build publishes them and
`nginx.conf` maps the extensionless `/privacy` and `/terms` onto them — the native apps and the
web build point at the same URLs. Both are overridable at build time
(`--dart-define=PRIVACY_URL=… --dart-define=TERMS_URL=…`), and `test/legal_links_test.dart`
guards the two ways this breaks quietly: a malformed URL, and a language missing the labels.

---

## 12. Onboarding, Tours and Telemetry

Three layers, all shipped:

- `widgets/help_sheet.dart` — always-available help and the glossary (opened from the shell
  and Personal Area).
- `widgets/coach_marks.dart` + `services/tour_service.dart` — per-tab spotlight tours, hooked
  into the shell's lazy tab build; a hand-rolled overlay rather than a package, to stay inside
  the design system.
- `widgets/activation_checklist.dart` — first-run checklist on the dashboard.

`services/telemetry.dart` posts events to `POST /api/events` → the `onboarding_events` table.
Design and the remaining measurement work: `docs/onboarding-help-plan.md`.

---

## 13. Build and Run

Compile-time configuration is all `--dart-define`; there are no `.env` files in the app.

| Define | Default | Purpose |
|---|---|---|
| `API_BASE` | `http://localhost:3000` | Backend base URL |
| `AUTH_EMULATOR` | *(unset)* | `host:port` of the Firebase Auth emulator |
| `RC_IOS_KEY` / `RC_ANDROID_KEY` | test-store key | RevenueCat SDK keys |
| `FIREBASE_VAPID_KEY` | bundled | Web push certificate |

```bash
# Development
flutter run -d chrome --dart-define=API_BASE=http://localhost:3000
flutter run           --dart-define=API_BASE=http://localhost:3000    # iOS device/simulator
flutter run           --dart-define=API_BASE=http://10.0.2.2:3000     # Android emulator

# Against the local stack with emulated identity
flutter run -d chrome \
  --dart-define=AUTH_EMULATOR=localhost:9099 \
  --dart-define=API_BASE=http://localhost:4010

# Release
flutter build web       --dart-define=API_BASE=https://mycarecoins.app
flutter build ipa       --dart-define=API_BASE=https://mycarecoins.app --dart-define=RC_IOS_KEY=appl_…
flutter build appbundle --dart-define=API_BASE=https://mycarecoins.app --dart-define=RC_ANDROID_KEY=goog_…
```

The web build is what the `fluterFront` Docker image serves through nginx. Store steps:
`docs/deployment-and-delivery.md`, which covers the server and both stores.

---

## 14. Testing

```bash
flutter analyze     # must be clean
flutter test        # 44 tests
```

`test/` covers the pure logic and the widget contracts that are cheap to assert and expensive
to get wrong: locale resolution and key parity across all four languages
(`l10n_test.dart`, `locale_test.dart`), error localization, activity kinds, starter packs, the
absence dialog's window rules, the personal-time sheet (types, repeats, and that the sheet
seeds its window from the tapped slot), and the legal-link contract (`legal_links_test.dart`).

There is **no end-to-end layer** — see `docs/automatic-testing-E2E.md`, which names that gap
and the shape a Flutter one (`integration_test/` + `flutter drive`) would take.

---

## 15. Platform Notes and Gotchas

- **iOS build directory must stay outside iCloud.** The repo lives in iCloud Drive, and
  `codesign` rejects the `FinderInfo` extended attributes iCloud attaches. Keep
  `fluterFront/build` symlinked to a location outside the synced folder.
- **Avatar upload is gallery-only** (`ImageSource.gallery` in `utils/avatar_upload.dart`).
  That is why `Info.plist` carries `NSPhotoLibraryUsageDescription` and deliberately no
  `NSCameraUsageDescription` — adding a camera path means adding that key, or iOS will
  terminate the app on first use.
- **Android release signing** currently falls back to the debug config in
  `android/app/build.gradle.kts`. Play rejects debug-signed uploads; wire a real
  `signingConfigs.release` before the first upload (`docs/deployment-and-delivery.md` §5).
- **Google Sign-In needs the right SHA-1s in Firebase** — both the upload keystore's and the
  Play App Signing one — or production sign-in fails with error code 10 while debug works.
- **Switching a simulator between production Firebase and the auth emulator needs
  `xcrun simctl erase`.** Firebase persists the session in the iOS **keychain**, which
  survives `flutter run`, an app reinstall, and `simctl uninstall`. The old session is
  restored, the new backend rejects its token, and every call fails with
  `Invalid or expired token`. Erasing the device is the only reliable reset:

  ```bash
  xcrun simctl shutdown <udid> && xcrun simctl erase <udid> && xcrun simctl boot <udid>
  ```

- **`ApiClient`'s doc comment says 10s; the code uses 20s.** The code is what runs.
