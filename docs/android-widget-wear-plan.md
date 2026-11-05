# Android widget, ongoing notification and Wear OS app: fast tasks — plan

**Status (2026-11-05):** Phases A0–A5 built on `main` (local, not pushed), builds and unit tests green. **Not yet run on an emulator or device** (A6 waits for Android Studio). The Android counterpart of
`docs/ios-widget-watch-plan.md`, which stays the reference for the product rules. The server side
(`/api/quick`, device keys, `cancel`) is shared and needs no change. It is **not deployed** yet, so test
against the local stack.

## 1. Goal

The same as iOS (`ios-widget-watch-plan.md` §1, §9): caregivers start, finish or log care in one or two
taps without opening the app. Caregivers only. The owner chose on 2026-11-05 to build the widget, the
ongoing notification **and** the Wear OS app in one go.

| iOS | Android |
|---|---|
| WidgetKit small / medium / large | **Jetpack Glance** app widget, one widget with responsive sizes |
| App Intents | Glance `ActionCallback`s |
| Live Activity (Lock Screen, Dynamic Island) | **Ongoing notification** with a chronometer and actions; an Android 16 **Live Update** (`ProgressStyle`, promoted ongoing) where available |
| Control Center controls | Quick Settings tile "Start care now" |
| App Group + shared keychain | The app's own private storage: the widget runs in the app process. Key encrypted with an Android Keystore AES key |
| WatchConnectivity `updateApplicationContext` | Wearable **Data Layer** `DataClient` item `/carecoins/context` |
| watchOS app (SwiftUI) | **Wear OS app** (Compose for Wear OS, Material 3) |
| Complications | Wear **complication data sources** (balance, next task) and a **Tile** |
| Local `UNNotificationRequest` reminders | Local notifications on the watch at `startsAt − 15 min` |

## 2. Product rules (identical to iOS)

- **Unplanned** (`snapshot.running`, Care now / Household now): elapsed time counting up, **Stop**.
- **Predefined** (a started template): it is all or nothing. Starting it books now → now + duration.
  - While it's on: a **countdown** to `endsAt`, "Until 19:30", and **Done** only. There is no Stop.
  - After `endsAt`: "Did you finish *X*?" with **Done** (`/quick/done {activityId}`) or **Not done**
    (`/quick/cancel`).
- **Undo** within 30 s of a Start or Done, and never after Stop.
- Errors use the server codes, with the strings ported from `Localizable.xcstrings`.

## 3. Architecture

```
 Phone (one process)                                          Server
 ┌──────────────────────────┐
 │ Flutter app              │ MethodChannel('carecoins/extensions') — same 5 methods as iOS
 │  Me ▸ Widget & Watch     │──▶ MainActivity.kt ──▶ :quickcore (key, snapshot, API)
 ├──────────────────────────┤                                     │
 │ Glance widget, Ongoing   │──── HTTPS (Authorization: Device) ──┼──▶ /api/quick/*
 │ notification, QS tile,   │                                     │
 │ WorkManager refresh      │                                     │
 └────────────┬─────────────┘                                     │
              │ Data Layer DataItem /carecoins/context            │
 Wear OS      ▼                                                   │
 ┌──────────────────────────┐                                     │
 │ Wear app, Tile,          │──── HTTPS (own network or phone's) ─┘
 │ complications, reminders │
 └──────────────────────────┘
```

### 3.1 Gradle modules (`fluterFront/android/`)

- **`:quickcore`** is an Android library shared by the phone and the watch. It is the port of
  `ios/Shared/`:
  - `QuickModels.kt`: `QuickSnapshot`, `Task`, `Upcoming`, `Running`, `QuickActionResult`, `LastAction`,
    flexible int/string decoding, and `startedTask` / `awaitingConfirmation` / `nextUpcoming`;
  - `QuickApi.kt`: snapshot, start, startNow, done, finish, stop, undo, cancel; error code mapping;
  - `DeviceKeyStore.kt`: Keystore AES-GCM wraps the key in private `SharedPreferences`;
  - `SnapshotStore.kt`: `quick.json` and `lastAction.json` in `filesDir`, plus the 30 s undo window;
  - `L10n.kt`: strings in the app language, which may differ from the system language. It reads
    `flutter.language` and uses `createConfigurationContext`;
  - `Palette.kt`: the tokens from `Palette.swift`;
  - `res/values{,-es,-fr,-de}/strings.xml`: the widget and watch strings.
  - It uses only `org.json` and `HttpURLConnection`: no new third-party libraries.
- **`:app`** (Flutter host) gains Glance, WorkManager, `play-services-wearable` and coroutines.
- **`:wear`** is the Wear OS app: `minSdk 30`, the **same `applicationId`** and signing key as the
  phone (the Data Layer needs both), Compose for Wear OS Material 3, Tiles, and complication data
  sources.
- **The lead owns the Gradle files and dependencies,** as Xcode was on iOS. agy writes Kotlin, XML
  resources and Dart.

### 3.2 Flutter bridge

- `ExtensionsBridge.available` becomes iOS **or Android**. It keeps the same `MethodChannel` and
  methods: `storeDeviceKey`, `status`, `refresh`, `clear`, `setLanguage`.
- `MainActivity.kt` implements them on `:quickcore`.
  - It pushes `{deviceKey, apiBase, snapshot, language}` to the Data Layer.
  - `clear` deletes the item, so the watch disconnects.
- The "Widget & Watch" strings that say iPhone or Apple Watch get Android variants.

### 3.3 Local testing

- From the emulators, the API base is `http://10.0.2.2:3000`. Debug builds allow cleartext; release
  builds don't.
- The phone emulator uses an Android 16 Play image. The watch emulator uses a Wear OS 5+ image, paired
  through Android Studio's Device Manager pairing assistant.

## 4. Phases

| Phase | Ticket | Content |
|---|---|---|
| A0 | lead | Gradle modules, dependencies, manifests, stubs |
| A1 | QA-1 | `:quickcore` port with JVM unit tests (shared JSON fixtures), the Android bridge in `MainActivity.kt`, `ExtensionsBridge` on Android, Me ▸ Widget & Watch on Android |
| A2+A3 | QA-2 | Glance widget with responsive small / medium / large, every action, the running, started and confirm banners, WorkManager refresh every 30 min plus at `endsAt`; ongoing notification / Live Update; Quick Settings tile |
| A4 | QA-3 | Wear app: Data Layer receiver, task list, confirms, haptics, undo, offline queue |
| A5 | QA-4 | Wear tile, complications, reminders 15 min before |
| A6 | lead | Emulator verification, As built, Play listing notes |

## 5. Risks

- **Glance has no countdown text.** A `Chronometer` inside `AndroidRemoteViews` does it
  (`setChronometerCountDown`, API 24+).
- **The widget update budget.** Android throttles `updatePeriodMillis`, so refresh with WorkManager
  (at least 15 min) and update right after each action.
- **Live Updates are Android 16 or later.** Older versions get a plain ongoing notification with the
  same actions.
- **Wear pairing in the emulator** needs Android Studio, which the owner is installing on 2026-11-05.
- **Play listing.** The Wear app ships as its own APK/AAB in the same Play listing, with Wear OS
  screenshots and a review.

## 6. As built

All by agy (Gemini 4 Argon) from `.lead/QA-*.md`, reviewed and committed by the lead on 2026-11-05.

- **A0 (lead, `c7dd54a`, `3c22289`, `84016e7`):**
  - modules `:quickcore` (an Android library) and `:wear` (`minSdk 30`, the same `applicationId` as the
    phone);
  - the Compose compiler plugin on `:app`;
  - libraries: Glance 1.1.1, WorkManager 2.10.1, `play-services-wearable` 19.0.0, Wear Compose Material 3
    1.0.0, tiles 1.5.0 / protolayout 1.3.0, complications data source 1.2.1;
  - phone manifest: the widget receiver, the action receiver, the Quick Settings tile and
    `POST_PROMOTED_NOTIFICATIONS`;
  - wear manifest: the Data Layer listener, the tile, two complications and the reminder receiver with boot.
- **QA-1 (`d31b4d3`):**
  - `:quickcore` ports `ios/Shared/`: models, API, Keystore-wrapped key, snapshot store, L10n, palette, and
    the strings in en/es/fr/de. A JVM test checks key and placeholder parity across the four languages.
  - The Flutter `ExtensionsBridge` is enabled on Android, with `MainActivity` → `ExtensionsBridge.kt`.
  - `WearSync` pushes `/carecoins/context`.
  - Me ▸ Widget & Watch shows Android texts.
- **QA-2 (`1f90a0d`):**
  - `quick/QuickActions.kt` and `QuickRefresh`: the action layer, a 30-min worker, and a one-time worker at
    `endsAt`;
  - `QuickWidget.kt`, a responsive Glance widget. Chronometers are `AndroidRemoteViews` (count up for
    running, count down for started);
  - `QuickNotification.kt`: the ongoing notification, with `ProgressStyle` and a promoted-ongoing request on
    API 36;
  - `CareNowTileService`.
  - The pure state pickers live in `quickcore` (`QuickSurfaceState`) and are unit-tested.
- **QA-3 (`64dcb50`):**
  - the Wear app: `WearContextListener`, `WearStore` with haptics, undo, a 12 h offline queue and
    `WearRefreshWorker`;
  - a Compose `TransformingLazyColumn` UI with the running, started, confirm, now, tasks and coins
    sections.
- **QA-4 (`eae9fd4`):**
  - a protolayout Material 3 tile, with timeline entries;
  - Balance and Next complications. Next uses `SuspendingTimelineComplicationDataSourceService`, so the
    started → confirm flip happens without the app;
  - reminders through `AlarmManager.setWindow`, at most 20, with Snooze 5 min, rescheduling after boot, and a
    setting toggle.
- **Open:** A6, running everything on emulators. The Play listing for the Wear APK is also open.
