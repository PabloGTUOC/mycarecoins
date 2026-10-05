# CareCoins — Flutter frontend (`fluterFront`)

**The** CareCoins frontend, targeting **web, iOS and Android** from one codebase. It talks
to `../backend` (port 3000 by default) with Firebase-ID-token auth.

## What is in the app

- **Design system** (`lib/theme/app_theme.dart`): the tokens documented in `docs/DESIGN.md`
  (colors, radii, Plus Jakarta Sans via `google_fonts`), plus `VCard`, `VButton`, `VInput`,
  `KpiCard` and the pill header / bottom tab bar (`lib/widgets/ui.dart`,
  `lib/screens/shell.dart`).
- **State + API** (`lib/state/app_state.dart`, `lib/services/api_client.dart`):
  Firebase auth (email/password + Google), `/api/me`
  sync, login/logout events, success/error toasts with the same timings.
- **Screens**: Landing page, Login (email/Google, autofill, forgot-password), Onboarding
  wizard (create family with caretakers + objects of care / join by token / invitations),
  Family Hub dashboard (member cards, paginated week strip with absences, offers, KPIs,
  activity feed), Daily (hour-grid timeline with drag & drop on tablets/desktop, timeline
  list with day-swipe and swipe-to-remove on phones, bounties, recurrence, absences),
  Activities (Catalogue / New Activity with budget-bounded coin slider / Budget gauge),
  Marketplace (Store / History / Create with validity dates), Stats (all ten panels +
  compare-caregivers toggle), Personal Area (account settings, avatar upload, notification
  preferences, dark wallet + ledger with revert, Family Circle with QR invite links,
  deletion requests). Pull-to-refresh and error/retry states on all main screens; FCM
  push notifications wired end-to-end in code.

`MOBILE_AUDIT.md` is a **dated July 2026 audit kept as history** — it predates personal time, coverage,
subscriptions and the four-language rollout, so check it against the code before acting on
anything it lists. Features shipped since are logged in `docs/personal-time-plan.md`,
`docs/admin-family-management-plan.md` and `docs/i18n-plan.md`.

## Running it

```bash
cd fluterFront
flutter pub get

# Web (Chrome)
flutter run -d chrome --dart-define=API_BASE=http://localhost:3000

# iOS simulator / Android emulator
flutter run --dart-define=API_BASE=http://localhost:3000     # iOS
flutter run --dart-define=API_BASE=http://10.0.2.2:3000      # Android emulator
```

The backend URL defaults to `http://localhost:3000`; override with `--dart-define=API_BASE=…`
(use your machine's LAN IP for a physical phone). The backend is plain HTTP, so both
platform shells currently opt out of cleartext blocking (`usesCleartextTraffic` on Android,
`NSAllowsArbitraryLoads` on iOS) — **remove both once the backend is served over HTTPS**.

### Local end-to-end testing without the real Firebase project

The app supports the Firebase Auth Emulator (pairs with the backend's `npm run dev:test`),
so the full stack runs offline with throwaway accounts:

```bash
firebase emulators:start --only auth --project tfg-carecoins   # port 9099
cd backend && FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 FIREBASE_PROJECT_ID=tfg-carecoins \
  DATABASE_URL=postgres://… ALLOWED_ORIGINS=http://localhost:8080 RESEND_API_KEY=re_dummy \
  node src/server.js
cd fluterFront && flutter run --dart-define=AUTH_EMULATOR=localhost:9099
```

## Firebase setup

Firebase is configured for **web, Android and iOS** against project `tfg-carecoins`:
`lib/firebase_options.dart`, `android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist` are all checked in (the iOS Dart options were
hand-written from the plist because `flutterfire configure --platforms=ios` needs the
`xcodeproj` gem; values are identical). The Google Sign-In reversed client ID URL scheme
is registered in `ios/Runner/Info.plist`.

Still required, once per environment:

- **Android Google Sign-In**: register the signing SHA-1 in
  [Firebase console → Project settings → Android app], then re-download
  `google-services.json`. Get the debug SHA-1 with
  `keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android`
  (also register the release/Play-signing SHA-1 before shipping). Without this,
  Google Sign-In fails with error code 10.
- **iOS push**: on a Mac, add the Push Notifications capability in Xcode and upload an
  APNs key in [Firebase console → Cloud Messaging]. `UIBackgroundModes:
  remote-notification` is already in `Info.plist`.

## Platform folders

`android/`, `ios/` and `web/` are generated with `flutter create`. If they are missing
(fresh checkout), regenerate them without touching `lib/`:

```bash
cd fluterFront
flutter create --org com.carecoins --project-name carecoins_flutter --platforms web,ios,android .
```
