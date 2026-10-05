# Flutter frontend (`fluterFront`) — mobile audit

> **Historical: audited 2026-07-07 at commit `e4cf875`.** Much has shipped since —
> personal time and coverage, subscriptions and the admin console, the four-language
> rollout, and the onboarding help layers. Treat the open-points list below as a snapshot,
> not a to-do: check each item against the code before acting on it. Current status lives in
> `docs/personal-time-plan.md`, `docs/admin-family-management-plan.md`,
> `docs/i18n-plan.md` and `docs/onboarding-help-plan.md`.

Audit date: **2026-07-07** (state as of commit `e4cf875 "Flutter ongoing"`).
Scope: full read of `lib/` (~9,000 lines, 22 files), `test/`, `android/`, `ios/`, `web/`,
`pubspec.yaml` and `README.md`.
Focus: **what is still open and where the app must improve to be a real mobile app**
(iOS / Android), as opposed to a web app that happens to run on a phone.

---

## 1. Where the port stands today

The feature set is essentially **complete**. All screens exist:
landing, login (email + Google), onboarding wizard, shell with pill header + bottom
tabs, Family Hub dashboard, Daily (hour-grid with drag & drop on wide, timeline list
with swipe on narrow), Activities (catalogue / create / budget), Marketplace, all ten
Stats panels with the compare-caregivers toggle, and the Personal Area (account
settings, wallet + ledger with revert, Family Circle with QR invites, notification
preferences). Avatar upload and FCM push are wired in. Batch 4 (push) is committed in
`e4cf875`, but the work is still **unverified**: `flutter analyze` and a build have not been run
on it, and no push message has ever been sent end-to-end.

What remains is not parity work. It is the gap between "runs in Chrome on a dev
machine" and "installable, reliable app on a phone". That gap is itemised below.

Priorities: **P0** = release blocker · **P1** = high-impact mobile UX/robustness ·
**P2** = polish, accessibility, hygiene.

---

## 2. P0 — Release blockers (app does not work on a device without these)

> **Status update (2026-07-07, same day):** everything that can live in the
> repo is done; three steps remain that require external consoles/hardware.
>
> - §2.1 ✅ `INTERNET` declared in the main manifest.
> - §2.2 ✅ cleartext HTTP enabled for the dev backend on both platforms
>   (`usesCleartextTraffic` / ATS `NSAllowsArbitraryLoads`, each commented as
>   dev-only). ⚠️ Remaining decision: serve the backend over HTTPS for any
>   real release, then remove both opt-outs. `API_BASE` still defaults to
>   `http://localhost:3000` — override per device via `--dart-define`.
> - §2.3 ✅ iOS `FirebaseOptions` hand-written from `GoogleService-Info.plist`
>   (identical to flutterfire output), reversed-client-ID URL scheme and
>   `remote-notification` background mode added to `Info.plist`. Firebase
>   init and Google Sign-In are now unblocked on iOS. ⚠️ Remaining, needs a
>   Mac + console: first `pod install`/Xcode build, Push Notifications
>   capability, APNs key upload.
> - §2.4 ⚠️ external only: Google Sign-In SHA-1 is confirmed unregistered
>   (`google-services.json` has no cert-hash OAuth client). Steps documented
>   in the README ("Android Google Sign-In" section).
> - §2.5 ✅ `POST_NOTIFICATIONS` declared in the main manifest.
> - §2.6 ✅ `flutter analyze` (no issues), `flutter test` (pass) and
>   `flutter build web` (success) run on Flutter 3.44.5 stable for this and
>   the P1 commit. ⚠️ `flutter build apk` still unverified — no Android SDK
>   in this environment. Push end-to-end test still open.
> - §2.7 ✅ app renamed to "CareCoins" (Android label, iOS display name, web
>   title/manifest/description) and branded launcher icons (accent-gradient
>   ¢, matching the in-app logo) generated for Android mipmaps, the full iOS
>   AppIcon set (no alpha) and web icons + favicon. Splash stays default
>   white — acceptable against the app's near-white background.

### 2.1 Android release builds have no network access
`android/app/src/main/AndroidManifest.xml` does not declare
`android.permission.INTERNET`. Only the `debug/` and `profile/` manifests do (Flutter
adds it there for hot reload). A **release APK/AAB cannot make a single HTTP call** —
Firebase auth and every API request will fail. Add to the main manifest:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### 2.2 Cleartext HTTP will be blocked on both platforms
`ApiClient.apiBase` defaults to `http://localhost:3000` (`lib/services/api_client.dart:18`).
On a real device:
- `localhost` is the phone itself, so the default is always wrong outside an emulator.
- Android 9+ blocks cleartext HTTP entirely unless `usesCleartextTraffic="true"` or a
  network-security-config is added; iOS ATS blocks it unless an exception is added.

Decision needed: either ship a real HTTPS backend URL as the default (with
`--dart-define=API_BASE` for dev), or add the cleartext opt-outs for a dev-only build.
There is currently **no notion of a production environment** anywhere in the project
(same issue for `kWebAppOrigin` in `lib/widgets/family_circle.dart:13`, which defaults
to `http://localhost:5173` — invite links and QR codes generated from a phone are
dead links unless overridden at build time).

### 2.3 iOS is non-functional: Firebase never initialises
`lib/firebase_options.dart` throws `UnsupportedError` for `TargetPlatform.iOS`
(flutterfire was only configured for web + Android). `main()` catches the throw and
sets `firebaseAvailable = false`, after which **login on iOS is impossible** —
`AppState.login()` calls `FirebaseAuth.instance` on a non-initialised app and throws.
`ios/Runner/GoogleService-Info.plist` exists, but the Dart options block is missing.
Open items:
- `sudo gem install xcodeproj`, then `flutterfire configure --platforms=ios`.
- Google Sign-In on iOS additionally needs the reversed client ID URL scheme in
  `Info.plist` (documented in README, not done).
- APNs key upload + push capability in Xcode for FCM.

### 2.4 Google Sign-In on Android needs the SHA-1 registered
`google_sign_in` on Android silently fails (error 10) if the signing certificate's
SHA-1 is not registered in the Firebase console for `com.carecoins.carecoins_flutter`.
Register both the debug keystore SHA-1 and, later, the release/Play-signing SHA-1.
Nothing in the repo records that this was done.

### 2.5 Push on Android 13+: `POST_NOTIFICATIONS` not declared
Android 13+ requires the runtime `POST_NOTIFICATIONS` permission for any notification
to be shown. `PushService.enable()` calls `FirebaseMessaging.requestPermission()`,
but the permission is not declared in the main manifest. Verify whether the
firebase_messaging plugin manifest merges it in; if not, declare it explicitly, or
notifications will be silently dropped on Android 13+ devices.

### 2.6 Verification debt on the current HEAD
The `e4cf875` commit (push work, ApiClient body-on-DELETE change, profile rewiring)
has never been through `flutter analyze` or `flutter build`. Flutter is not available
in this audit environment, so it remains unverified. Before anything else:
`flutter analyze && flutter test && flutter build web && flutter build apk --debug`.
Also still open: a real end-to-end push test (token row in
`fcm_tokens`, foreground toast, background notification) and end-to-end exercising of
the screens against the running backend.

### 2.7 App identity is still the Flutter template
- Android launcher label is `carecoins_flutter` (`AndroidManifest.xml`), icons are
  the stock Flutter icons, no adaptive icon, default splash.
- `web/index.html`: `<title>carecoins_flutter</title>`,
  `<meta name="description" content="A new Flutter project.">`.
- No versioning strategy (`pubspec.yaml` at 0.1.0, gradle takes flutter defaults).

Low effort, but it is what a tribunal/user sees first on a home screen.

---

## 3. P1 — High-impact mobile UX and robustness

> **Status update (2026-07-07, same day):** all ten P1 items below were
> implemented in the follow-up commit on this branch. Per-item notes:
> §3.1 ✅ `touchAwareDraggable` (long-press on touch) · §3.2 ✅ `isWideLayout()`
> (width + shortestSide ≥ 600) · §3.3 ✅ lazy tab build + refetch-on-activation
> (`active` prop) + dashboard reload when Daily pops · §3.4 ✅ pull-to-refresh on
> both Daily layouts, "Tasks Today" KPI opens today's Daily · §3.5 ✅ `.toLocal()`
> on dashboard bucketing/formatting, hour labels now 24h · §3.6 ✅ `LoadErrorState`
> + retry on the five load screens, human-readable network errors, 20s timeout
> · §3.7 ✅ larger hit areas (timeline pills, week pagination 44px, dependent-remove ✕);
> the *compact* grid-chip pills keep their size (pointer-first surface)
> · §3.8 ✅ autofill/keyboard actions/submit-on-enter + forgot-password + app-wide
> toasts (previously login errors were invisible — Shell owned the only listener)
> · §3.9 ✅ textScaler clamped at 1.3 (containers not yet flexible), SegmentedTabs
> FittedBox · §3.10 ✅ `cacheWidth` + `gaplessPlayback` (disk cache via
> `cached_network_image` deferred — new dependency needs a `pub get`).
>
> **UX drive (2026-07-07):** the logged-out surface was exercised end-to-end in
> a script-driven Chromium at a 390×844 phone viewport (and 844×390
> landscape) against the real web build with the real Firebase SDK: landing
> scroll + CTAs, login, typing, Enter-to-submit, empty-field toast, real
> invalid-credential toast (root ToastListener confirmed on logged-out
> screens), forgot-password dialog, register toggle, back navigation,
> landscape keeping the mobile layout. One bug found & fixed: `VInput` used
> directly as `AlertDialog` content stretched the reset-password dialog to
> full screen height (missing `mainAxisSize: min`). Logged-in screens remain
> undriven — they need the backend + a test account.
>
> **Logged-in UX drive (2026-07-07, later same day):** full stack run locally —
> Postgres 16 + the real backend + the **Firebase Auth Emulator** (new
> `--dart-define=AUTH_EMULATOR=host:port` hook in `main.dart`, matching the
> backend's `npm run dev:test`; nothing touched the production Firebase
> project). Driven end-to-end at the phone viewport: register → onboarding
> wizard (family + care object) → Family Hub (member cards, week strip,
> KPIs) → all five tabs (lazy build + active refetch working) → "Tasks
> Today" KPI → Daily → FAB → task sheet → schedule dialog → scheduled card
> with gap indicator + success toast. Findings fixed: onboarding caretaker
> placeholders truncated on 390dp ("Name (op…"), and the care-time dropdown
> label collided with its arrow (now `isExpanded` + ellipsis). Known
> cosmetic, dev-only: the auth-emulator warning banner overlays the bottom
> tab bar. Still unexercised: validate/bounty/revert lifecycle (needs a
> second account), marketplace redeem, avatar upload, push.

### 3.1 Drag & drop uses `Draggable`, which breaks touch scrolling
`daily_screen.dart:1371` (Task Library rows) and `daily_screen.dart:999` (scheduled
chips) use `Draggable`, which grabs the pointer **immediately**. On a touchscreen,
trying to scroll the task list or the hour grid by touching a card starts a drag
instead — the grid becomes effectively unscrollable wherever chips sit. The wide
layout is not desktop-only: it activates on any width > 768 (see 3.2), i.e. most
tablets and phones in landscape. Fix: use `LongPressDraggable` when the platform is
touch (or gate on `PointerDeviceKind`), keeping `Draggable` for mouse.

### 3.2 The wide/narrow breakpoint mis-classifies phones in landscape
`kMobileBreakpoint = 768` is compared against **width** everywhere
(`shell.dart:78`, `daily_screen.dart:621`, etc.). An iPhone 14 in landscape is
844 logical px wide → it gets the desktop pill nav (bottom tab bar disappears) and
the Daily drag-and-drop grid. Rotating the phone mid-session silently swaps the whole
navigation paradigm. Consider `MediaQuery.sizeOf(context).shortestSide < 600` (the
standard phone/tablet test) or checking orientation before switching layouts.

### 3.3 All five tabs load eagerly and then go permanently stale
`Shell` builds all screens inside an `IndexedStack` (`shell.dart:104`), so on startup
the app fires ~10 API calls at once (dashboard 4, activities 2, marketplace 1,
stats 1, profile 2–3) — wasteful on mobile data and slow on a cold start. Worse,
each screen loads only in `initState`, so **data never refreshes when switching
tabs**: validate a task in Daily, return to the Dashboard, and the KPIs / week strip
still show the old state until the user discovers pull-to-refresh. Options:
lazy-build tabs on first visit, refetch on tab activation (cheap: compare `_index`
in `didUpdateWidget` or use a per-tab `visibilityChanged`), or move shared data
(activities, absences) into `AppState` so one refresh feeds all screens.

### 3.4 Daily view: no pull-to-refresh and buried entry point
- Daily is the only main screen without `RefreshIndicator` (`daily_screen.dart` body
  is a plain `Column`/`ListView`); on mobile there is no way to refetch except
  re-entering the screen.
- Daily is reachable **only** by tapping a day column inside the dashboard's
  horizontally-scrolling week strip. On a phone that is two gestures deep for the
  screen users will open most often. Consider a "Today" entry: a bottom-bar tab, a
  dashboard shortcut button, or making the "Tasks Today" KPI open Daily instead of
  Stats.

### 3.5 UTC/local inconsistency on the dashboard (real bug)
`daily_screen.dart` correctly does `.toLocal()` on `starts_at`
(`_startsAt`, line 105). The dashboard does **not**:
- `_actsOn` (`dashboard_screen.dart:136`) buckets activities into week-strip days
  using the *UTC* date → tasks near midnight appear on the wrong day, and differ
  from what Daily shows for the same day.
- `_ActChip` (line 862) and the offer rows (line 427) format times without
  `.toLocal()` → chips show UTC clock times while Daily shows local ones.

Same class of issue: `_hourLabel` in Daily renders "1:00 PM" 12-hour labels while
every chip/card shows 24-hour `HH:mm` — pick one convention (or use
`MediaQuery.alwaysUse24HourFormat`).

### 3.6 Failures are silent: every load error looks like "no data"
Every screen's `_load()` ends in `catch (_) { setState(() => _loading = false); }`
(`dashboard_screen.dart:75`, `daily_screen.dart:84`, `stats_screen.dart:52`,
`marketplace_screen.dart:82`, `activities_screen.dart:67`, plus the swallowed
catches in `profile_screen.dart` and `family_circle.dart`). On a flaky mobile
connection the user sees "No stats available yet." / an empty store / an empty day —
indistinguishable from genuinely having no data, with no retry affordance. Minimum
fix: keep an `_error` flag and render an error state with a Retry button; ideally add
a tiny retry/backoff in `ApiClient` for idempotent GETs. Related: the 10 s fixed
timeout in `api_client.dart:37` is aggressive for cellular; uploads get 30 s but
GETs of the dashboard payload get 10.

### 3.7 Touch targets below the 44–48 dp guideline
- `_ActivityAction` pills (`daily_screen.dart:1164`): compact variant is ~22 px tall,
  regular ~30 px — these are the primary **Validate / Delegate / Take Over** actions.
- "Un-check" ledger button constrained to 28 px (`profile_screen.dart:921`).
- Dependent-remove ✕ is a 22 px circle (`family_circle.dart:496`).
- Week pagination `«`/`»` are 36 px (`dashboard_screen.dart:638`).

Wrap small visuals in a larger hit area (`SizedBox` ≥ 44 px + `InkWell`, or
`materialTapTargetSize`) without changing the visual design.

### 3.8 Text fields are not mobile-ready
`VInput` (`widgets/ui.dart:137`) exposes no `autofillHints`, `textInputAction`,
`onSubmitted`, or `autocorrect` control. Consequences on a phone:
- No password-manager integration on login (`AutofillHints.email` /
  `AutofillHints.password` + an `AutofillGroup` are missing), no "Enter" to submit —
  the user must tap the button behind the keyboard.
- Profile email (`profile_screen.dart:535`) and onboarding caretaker emails
  (`onboarding_screen.dart:355`) use the default keyboard instead of
  `TextInputType.emailAddress`.
- No "forgot password" flow at all (Firebase's `sendPasswordResetEmail` is one call);
  on mobile, account recovery matters more because typing is error-prone.

### 3.9 Large font sizes will break fixed-height chrome
The app hardcodes many tiny font sizes (9–11 px chips, 10 px bottom-tab labels) inside
fixed-height boxes (bottom bar `SizedBox(height: 60)` in `shell.dart:129`, hour-grid
chips clamped at 46 px, `_DayColumn` minHeight 220). With the OS font scale at 130 %+
(common accessibility setting), these overflow with striped errors. Either clamp
`MediaQuery.textScaler` at the app root (quick fix) or audit the fixed-height
containers (right fix). `SegmentedTabs` (`ui.dart:411`) also overflows on 320 dp-wide
phones with three long labels ("Catalogue / New Activity / Budget") — it needs
`Flexible` children or a horizontal scroll.

### 3.10 Avatars re-download on every rebuild
`AvatarCircle` uses raw `Image.network` (`ui.dart:372`). No disk cache, no
`loadingBuilder` — avatars flicker and re-fetch on tab switches and rebuilds; on
mobile data this is repeated waste for images that never change. Add
`cached_network_image` (or at minimum a `CircleAvatar` + `NetworkImage`, which uses
the in-memory image cache keyed by URL) and a placeholder.

---

## 4. P2 — Polish, accessibility, hygiene

### 4.1 Accessibility / semantics
- Emoji are used as functional icons everywhere (❤️ 🍽️ ✈️ 📷 🔁 ⚠️) with no
  `Semantics` labels — screen readers will read "red heart" instead of "care task".
- Custom `InkWell`/`GestureDetector` tabs (bottom bar, `SegmentedTabs`) carry no
  `Semantics(selected:, button:)`; Material's `NavigationBar`/`TabBar` would give
  this for free plus tooltips, haptics, and badges.
- Charts (`widgets/charts.dart`) are pure `CustomPaint` with no semantics or
  touch feedback (no tooltips/tap-to-inspect values) — fine for a first pass, worth
  noting for the stats-heavy tribunal demo.
- No dark mode: all colors are hardcoded light-theme constants
  (`theme/app_theme.dart`); `MaterialApp` sets no `darkTheme`. Acceptable scope cut —
  document it as such.

### 4.2 Swipe-gesture collisions on the narrow Daily
`_buildNarrow` wraps the whole list in `onHorizontalDragEnd` for day-swiping
(`daily_screen.dart:1017`) while every card is a horizontal `Dismissible`. The
gestures resolve deterministically (cards win), but the result is that day-swipe only
works when started on empty space / gap rows — which is undiscoverable and feels
broken. Consider a `PageView` per day (real paging physics + animation) or reserved
swipe zones; at minimum animate the day change so a successful swipe gives feedback.

### 4.3 State-management seams
- `AppState` is a single `ChangeNotifier` watched by the shell and most screens;
  every toast (`setSuccess`/`setError`) rebuilds all watchers, and `_showToasts`
  runs as a side effect of `build` (`shell.dart:79`) with manual dedupe via
  `_lastToast`. Works, but fragile — the same message twice in a row is suppressed.
  Moving toasts to a stream/listener (`context.select` or a `listen:` callback)
  would decouple rebuilds from toast delivery.
- `ProfileScreen` copies profile values into its text controllers once in
  `initState` (`profile_screen.dart:50-52`). Because the IndexedStack constructs it
  at app start, a later profile/alias change (e.g. after resume-refetch) never
  reaches the fields.
- Raw `e.toString()` becomes the user-facing toast in `runAction`
  (`app_state.dart:174`) — `TimeoutException after 0:00:10.000000: …` is not a
  mobile-friendly error message. Map common failures (timeout, socket, 401) to
  human text.

### 4.4 Deep links and URL routing
Still open: no `go_router`, no `/join?token=…` handling, no iOS Universal
Links / Android App Links. QR codes generated in-app point at the web origin.
It is the single feature where "mobile
app" and "QR-based family invites" meet — a scanned QR should open the native app's
join flow.

### 4.5 Testing and CI
- Exactly one widget smoke test exists (`test/widget_test.dart`, 3 asserts).
  The pure logic that most deserves tests is already extracted and testable without
  mocks: `_scheduledToday` overlap/gap math (`daily_screen.dart:110`), ledger
  labels/dates (`profile_screen.dart:659`), `formatGap`, `_coinTier`, budget
  min/max coins (`activities_screen.dart:79`).
- No CI runs `flutter analyze` / `flutter test` (the repo's workflows don't cover
  `fluterFront`), which is how unverified commits like `e4cf875` happen.
- No crash reporting or analytics for native builds (Crashlytics or Sentry) — on
  mobile you cannot read the console; without this, field failures are invisible.

### 4.6 Stale documentation
- `README.md` "Not ported yet" section still lists avatar upload, push, landing
  page, compare-toggle and deletion requests — **all of which are now ported**.

### 4.7 Small correctness notes (grouped)
- `dashboard_screen.dart:54` assumes `/api/activities` returns a map
  (`acts['activities']`); `daily_screen.dart:68` defensively handles list-or-map.
  Align on one.
- `_absenceDetail` (`daily_screen.dart:466`) lets any member delete any absence —
  no ownership check (verify against backend rules; the schedule-guard nearby does
  check `user_id`).
- `PushService._currentToken` is memory-only: after an app restart, `disable()`
  early-returns and never unregisters the token from the backend
  (`push_service.dart:70-71`). Persist the token (e.g. `shared_preferences`) or
  fetch it fresh before deleting.
- `onResume` callback uses `context.read` from a `State` that could be disposed
  (`shell.dart:33`) — guard with `mounted`.
- `firebase.json` at repo root plus `fluterFront/firebase.json` — double-check the
  root one doesn't confuse `flutterfire configure` runs.

---

## 5. Suggested order of attack

1. **Make a device build work at all**: INTERNET permission, API_BASE/cleartext
   strategy, verify + build current HEAD, register Android SHA-1
   (§2.1, §2.2, §2.4, §2.6).
2. **iOS bring-up**: flutterfire iOS config, reversed client ID, then APNs
   (§2.3, rest of §2.5).
3. **Touch correctness pass**: LongPressDraggable, breakpoint by shortestSide,
   touch-target sizes, Daily pull-to-refresh + entry point (§3.1, §3.2, §3.4, §3.7).
4. **Data freshness + failure UX**: tab refetch or shared state, error/retry
   states, dashboard `toLocal()` fixes (§3.3, §3.5, §3.6).
5. **Input & identity polish**: autofill/keyboard/submit actions, forgot-password,
   app name/icons/splash, avatar caching (§3.8, §2.7, §3.10).
6. **Hygiene**: font-scale audit, semantics, unit tests + CI, crash reporting,
   doc refresh (§3.9, §4.1, §4.5, §4.6).
7. **Deep links** when the native app becomes the primary QR target (§4.4).
