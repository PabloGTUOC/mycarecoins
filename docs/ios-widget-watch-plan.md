# iOS widget and Apple Watch app: fast tasks — plan

**Status (2026-10-23):** Phases 0–2 done on `main` (§10). The Phase 1 backend is **not deployed**, so
Connect fails against production until it is. Next: Phase 3 (iPhone widgets). The owner answered the open decisions on 2026-10-23 (§9).

## 1. Goal

Caregivers start, finish or log care in one or two taps without opening the app. PRODUCT.md §Users
describes the moment: "brief, high-stress moments: morning routines, handoffs… Mobile is the primary
device for quick task actions".

- **Home Screen widget:** your usual tasks as buttons (**Start** or **Done**), plus **Start care now** and
  **Start household now** for unplanned work.
- **Live Activity** (Lock Screen and Dynamic Island) while a task is running: a timer and a **Stop**
  button. On a paired watch it also appears in the Smart Stack.
- **Lock Screen and StandBy widget:** your balance and what needs you.
- **Apple Watch app:** the same start, done and log actions, plus a **reminder 15 min before** each of
  your scheduled tasks today.

**Caregivers only.** Members (dependents) don't see the "Widget & Watch" screen, and the server refuses
a device key for anyone who isn't an active caregiver.

Out of scope: creating templates, approving, validating, bounties, personal time, rewards, statistics.

## 2. The actions, in today's model

| Action | What the server does | Existing code |
|---|---|---|
| **Done** a usual task ("I just did it") | Schedules the template with `startsAt = now − duration`. If the user is the only caregiver, the instance is `approved` and the auto-complete sweep pays it; otherwise it is `pending_validation` | `scheduleActivity` (past start) |
| **Start** a usual task | Schedules the template at `now`, so it is `approved` and runs for the template's duration. The auto-complete sweep pays it at the end unless it is finished first | `scheduleActivity` |
| **Done** on a started task (early finish) | Completes the instance and pays its coins now | `completeActivity` |
| **Start care now / household now** (unplanned, real time) | Creates a one-off running instance with no template (§3.3) | **New** |
| **Stop** a running unplanned task | Fixes the end and the duration, works out the coins, then completes it | **New** |
| **Undo** (30 s after a Start or Done; the server allows 60 s) | Unschedules the instance if it has not been paid yet; if it has, reverts it with reversal rows (the ledger stays append-only). Not offered after Stop: fix the time in the app | `deleteActivity`, `revertActivity` |

Every rule still applies: the overlap check (409 `scheduleOverlap`), the absence check, the budget
warning, read-only (`past_due`) families, and the existing pushes to the other caregivers.

## 3. Architecture

```
 iPhone                                                       Server
 ┌──────────────────────────┐  App Group   ┌──────────────────────────┐
 │ Flutter app (Runner)     │──keychain───▶│ Widget ext.: WidgetKit,  │──HTTPS──▶ /api/quick/*
 │  Me ▸ Widget & Watch     │ + snapshot   │ AppIntents, Live Activity│        (device key)
 │  MethodChannel ↔ Swift   │              └──────────────────────────┘
 └────────────┬─────────────┘
              │ WatchConnectivity (device key + snapshot)
 Apple Watch  ▼
 ┌──────────────────────────┐
 │ watchOS app (SwiftUI),   │──HTTPS (own network or the phone's)──▶ /api/quick/*
 │ complications, local     │
 │ reminders                │
 └──────────────────────────┘
```

All new pieces are native SwiftUI. Flutter can't render widgets or watch apps; the Flutter app only hands
over a key and a cached snapshot.

### 3.1 Authentication: device keys

The API takes Firebase ID tokens (`middleware/auth.js`), which expire after an hour. A widget runs in
short bursts, and a watch can't share the phone's Firebase session. So each device gets a long-lived key
that only works on `/api/quick/*`:

- `POST /api/me/device-keys` (Firebase auth, **caregiver** in the family, at most 10 live keys) returns
  `{ id, key }` once. The key is 32 random bytes, base64url, prefixed `cck_`. The server stores only
  `sha256(key)`.
- New table `device_keys(id, user_id, family_id, label, key_hash UNIQUE, created_at, last_used_at,
  revoked_at)`. It goes into `FORBIDDEN_TABLES`, with an idempotent `migrate-device-keys.sql` mirrored in
  `schema.sql` and chained in `init-db.js`.
- Middleware `requireDeviceKey` handles `Authorization: Device cck_…`. On every request it checks that
  the key isn't revoked and that the user is **still an active caregiver** of that family, then sets
  `req.auth` the way `upsertUserFromAuth` expects, so the services don't change.
- It is mounted only on `/api/quick`, with its own rate limiter. Every other route still requires a
  Firebase token.
- `GET` and `DELETE /api/me/device-keys[/:id]` support listing and revoking keys in Me. Sign-out revokes
  the keys that phone created.
- New error codes go into `docs/error-codes.md`, the four ARB files, `server_errors.dart` and the native
  string catalog: `deviceKeyInvalid`, `deviceKeyRevoked`, `deviceKeyCaregiverOnly`, `quickTaskNotRunning`.

### 3.2 `/api/quick` endpoints

| Route | Purpose |
|---|---|
| `GET /api/quick` | `{ family, balance, needsYou, tasks[≤8], today[], running }`. `tasks` are the user's top templates, ranked like the Today tray. `today` holds the user's own instances for today (for reminders and for Done). `running` is the unplanned task in progress, if there is one |
| `POST /api/quick/start` | `{ templateId, clientRef }` → schedule at now; or `{ type: "care"\|"household", title?, clientRef }` → unplanned running task |
| `POST /api/quick/done` | `{ templateId, clientRef }` → logged as done just now; or `{ activityId }` → finish a started task early |
| `POST /api/quick/stop` | `{ activityId }` → stops the unplanned running task |
| `POST /api/quick/undo` | `{ clientRef }` → allowed for 30 s, only on the key owner's own instance |

- **Ranking moves to the server** (`services/quickService.js`, a port of `utils/tray_ranking.dart`), so the
  watch doesn't depend on when the phone last opened Today. Both implementations read one shared fixture,
  `tray_ranking_cases.json`, in their tests, so they can't drift.
- **`clientRef`** is a UUID made on the device, so an offline watch can safely retry. This needs a new
  nullable column `activities.client_ref`, with a partial unique index on `(assigned_to, client_ref)`.
- Only `category = 'care'` templates are offered. Personal time never appears.

### 3.3 Unplanned real-time tasks (new in the model)

Today every instance has a fixed end, and the auto-complete sweep (`db/autoComplete.js`) pays any
`approved` instance whose `ends_at` has passed. A running timer must not be paid early, so:

- **New column `activities.running_since timestamptz NULL`.** Start creates a non-template instance:
  `category 'care'`, the chosen `type`, `status 'approved'`, `starts_at = now`, and a placeholder
  `ends_at = now + 15 min`. The title is the dictated one or a localized default ("Care" / "Household");
  the device sends it already localized, because titles are stored as plain text. A unique index allows
  one running row per user.
- **The sweep skips rows with `running_since IS NOT NULL`.**
- **Stop** sets `ends_at = now`, with duration = elapsed minutes rounded up to 15 (minimum 15, the app's
  rule) and `coin_value` = minutes, the same default as `createActivity`. It clears `running_since` and
  then completes through the same payout path as `completeActivity`. All of this happens in one
  transaction, and the ledger is untouched until Stop.
- **One running task per user.** Starting another returns `409 quickTaskAlreadyRunning`.
- **Cap:** the sweep stops a task at 4 h and pays it as a 240-minute task. No push in v1. The time can be
  corrected in the app.
- Coins come out of the residual like any other log, so the economy doesn't change (CLAUDE.md, the
  two-layer rule).

### 3.4 Handing data to the extensions

- **App Group** `group.com.carecoins.carecoinsFlutter` and a **shared keychain item**
  `carecoins.deviceKey`.
- **Snapshot** `quick.json` in the App Group holds the last `GET /api/quick` result. Widgets render from it
  instantly. The app rewrites it and calls `WidgetCenter.shared.reloadAllTimelines()` after any change on
  Today.
- **Bridge:** a `MethodChannel('carecoins/extensions')` in `AppDelegate.swift` with `storeDeviceKey`,
  `clear`, `writeSnapshot` and `reloadWidgets`. No new Flutter dependency.
- **Watch:** the Runner calls `WCSession.updateApplicationContext({deviceKey, snapshot})`. After that the
  watch calls the server directly.

## 4. iPhone: widgets and Live Activity (iOS 27)

The widget extension targets the **latest iOS (27)**. The Runner itself stays at iOS 15, so older phones
keep the app and just don't get the widget. Raising the whole app's minimum is a separate decision.

| Surface | Content | Tap |
|---|---|---|
| `systemSmall` | Your top task (**Start** · **Done**), plus balance in the coin-pill style | Intents |
| `systemMedium` | 4 top tasks, each with Start and Done, plus **+ Care now** and **+ Household now** | Intents |
| `systemLarge` | 8 tasks, the two "now" buttons, and your next task today | Intents |
| Lock Screen / StandBy accessory | Balance and a "needs you" count | Opens the app at Today |
| **Live Activity** (Lock Screen, Dynamic Island) | The running task, an elapsed timer (`Text(timerInterval:)`), coins so far | **Stop**, or Done for a started template |
| Control Center controls | "Start care now" and "Log *top task*" | Intents |

- **Intents** (`StartTaskIntent`, `DoneTaskIntent`, `StopTaskIntent`, `UndoIntent`) run in the extension.
  Each one updates the snapshot first, so the chip shows "Started ✓" or "Logged ✓" at once, then calls the
  server. A Start begins the Live Activity, and a Stop or Done ends it.
- **Errors** show on the chip for one refresh. An overlap shows "Overlaps *title*" with an Open link.
- **Design:** DESIGN.md and the Wada tokens: `primary #006EB8`, `coinSoft`/`coinInk` for coins, soft fill
  with ink text, the system font. The tokens are duplicated in `Shared/Palette.swift`, and a guard test
  parses `app_theme.dart` (as PAL-2 does for `adminFront`). Tinted and clear rendering modes are handled.

## 5. Apple Watch (watchOS 27)

- **Main list:** the running task at the top (timer and **Stop**), then **+ Care now** and **+ Household
  now** (title by dictation, optional), then your top tasks with **Start** and **Done**. Each action has a
  confirm step and a success haptic, and offers Undo for 30 s.
- **Reminders 15 min before** every one of your scheduled tasks today. These are local
  `UNNotificationRequest`s on the watch, scheduled from `today[]` on every refresh (background refresh
  about every 30 min, and whenever the phone pushes a new snapshot). The notification has **Start** and
  **Snooze 5 min** actions. They are local to the watch, so they work without the phone nearby, and the
  phone doesn't duplicate them. The watch app has an on/off setting for them.
- **Complications:** balance, the next task with its start time, and the running timer.
- **Offline:** actions are queued by `clientRef` and sent when the connection returns, and the row shows
  "Waiting to send". The server dedupes them.
- **Pairing:** the watch needs the phone once to receive its key. After that it works on its own network.

## 6. Strings and accessibility

- The native targets share one **String Catalog**, `ios/Shared/Localizable.xcstrings`, in en, es, fr and
  de. A Flutter test (`native_strings_test.dart`) fails if any key is missing a language. This is the
  native counterpart of the ARB rule, as `adminFront/lib/strings.dart` is for the console.
- Template titles: default templates carry a `title_key`, and the catalog holds the same translations as
  `displayTitle`. Verify in Phase 1.
- Every button has a VoiceOver label ("Start Bath time, 30 minutes"). Dynamic Type works on the watch, and
  hit targets are ≥ 44 pt where the widget size allows.

## 7. Phases

Each phase gets its own branch and agy tickets. The lead reviews and commits. Merge, push and deploy need
the owner's OK.

| Phase | Content | Who | Done when |
|---|---|---|---|
| **0. Setup** | The owner signs in to Xcode with the Apple account and gives the Team ID. The lead turns on automatic signing, adds the Widget Extension and watchOS app targets in Xcode, plus the App Groups, Keychain Sharing and Push capabilities. Paired iPhone + Watch simulators | Owner + lead | `flutter build ios` and both empty targets build |
| **1. Backend** | `device_keys`, `requireDeviceKey`, `client_ref`, `running_since`, sweep exclusion and 4 h cap, `/api/quick/*`, ranking port + shared fixture, error codes, docs | agy (QW-1…QW-3) | `npm test`, `db:init` twice, `check-admin-role` |
| **2. App bridge** | Me ▸ "Widget & Watch" (caregivers only): connect, list, revoke; MethodChannel; keychain + snapshot; reload after Today changes; sign-out cleanup; WCSession; four ARB files | agy (QW-5) | `flutter analyze && flutter test`; key visible in the shared keychain on the simulator |
| **3. iPhone** | `Shared/` (API client, models, palette, strings), widgets, intents, Live Activity, controls, guard tests | agy (QW-5…QW-7) | Start, Stop, Done and Undo from the simulator Home Screen, reflected in Today |
| **4. Watch** | Watch app, confirm and haptics, local reminders, offline queue, complications | agy (QW-8, QW-9) | Same actions on the paired watch simulator with the phone app killed; a reminder fires 15 min early |
| **5. Release** | Backend deploy (owner's OK), TestFlight on a real phone and watch, App Review notes, `docs/deployment-and-delivery.md`, PRODUCT.md § "Widget and Watch" | Lead + owner | TestFlight pass on real devices |

## 8. Risks

- **agy and Xcode projects.** `project.pbxproj` breaks easily. The lead creates every target and
  capability in Xcode; agy only writes `.swift` and `.xcstrings` files into folders that already exist.
- **Production lags `main`.** Nothing works until `/api/quick` is deployed. Phase 5 deploys the backend
  before the TestFlight build.
- **Live Activities** are capped at 8 h by iOS. The 4 h server cap stays below that.
- **Widget refresh budget.** iOS limits timeline reloads. Intents reload after each action; otherwise
  every 30 min.
- **Simulator limits.** Interactive widgets, Live Activities and WatchConnectivity work in the simulator,
  but real push, LTE and latency don't, so a TestFlight pass is mandatory.
- **Privacy.** The Lock Screen shows the balance on a locked phone, so it is marked
  `privacySensitive()` and has a "hide on Lock Screen" setting.

## 9. Decisions (owner, 2026-10-23)

1. **Start and Done**, plus unplanned real-time **Care now / Household now** from the widget and the watch.
2. **Caregivers only.**
3. **Watch:** start, done and log, plus a **reminder 15 min before** each scheduled task.
4. **Latest OS versions** for the new targets (iOS 27, watchOS 27). The Runner stays at iOS 15.
5. Apple Developer account: Team ID `63CZCUTA77` (Individual, paid), signed in to Xcode. On 2026-10-23
   the owner registered the App Group `group.com.carecoins.carecoinsFlutter`, the App IDs `…carecoinsFlutter`,
   `.Widget`, `.watchkitapp` and `.watchkitapp.Widget`, and an APNs key for Firebase.

## 10. As built

### Phase 0 (2026-10-23, lead)

- **Targets** in `fluterFront/ios/Runner.xcodeproj`, added with the `xcodeproj` gem that ships with
  CocoaPods (not by hand):
  - `CareCoinsWidget`: iOS 27 widget extension (`.Widget`), embedded by Runner's "Embed Foundation
    Extensions" phase.
  - `CareCoinsWatch`: watchOS 27 app (`.watchkitapp`), embedded by "Embed Watch Content"
    (`$(CONTENTS_FOLDER_PATH)/Watch`).
  - `CareCoinsWatchWidget`: the watch complications (`.watchkitapp.Widget`), embedded in the watch app.

  Both embed phases sit **before Thin Binary**; after it, Flutter's script phases form a build cycle.
  Each target holds one placeholder file. The real code replaces it in Phases 3–4.
- **`Shared/CareCoinsShared.swift`**: the App Group, keychain group and key-account names. It is compiled
  into all four targets.
- **Signing:** team `63CZCUTA77` with automatic signing on every target.
  - `Runner/Runner.entitlements`: push (`aps-environment`), App Group, keychain group
    `$(AppIdentifierPrefix)com.carecoins.carecoinsFlutter.shared`.
  - The widget has the App Group and the keychain group; the watch targets have the App Group only.
- **Versions:** `Flutter/Extensions.xcconfig` includes `Generated.xcconfig`. The new targets use
  `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)`, so they always match the app, which the App Store
  requires.
- **Gotchas found:**
  - The Flutter project sets `SUPPORTED_PLATFORMS = iphoneos` at the project level. The watch targets
    override it (`watchos watchsimulator`), or the archive compiles them against the iOS SDK.
  - `PRODUCT_NAME = $(TARGET_NAME)` must be set on new targets, or the build fails with "Multiple
    commands produce .appex".
  - With a watch app present, `flutter build ios --simulator` and `flutter run` need `-d <device id>`.
- **Verified:**
  - `flutter build ios --simulator -d <iPhone 17e>` builds.
  - `xcodebuild archive -allowProvisioningUpdates` succeeds, with all four bundles signed by the team
    and carrying the expected entitlements.
  - The watch app launches on the Series 12 simulator, paired with the iPhone 17e simulator.

### Phase 1 (2026-10-23, agy QW-1…QW-4, reviewed by the lead)

- **QW-1 `00ddeb8` — device keys.**
  - `device_keys` table, in `FORBIDDEN_TABLES`.
  - `deviceKeyService` and the `requireDeviceKey` middleware.
  - `/api/me/device-keys` routes: create, list, revoke, revoke all.
- **QW-2 `0ad6e19` — ranking and running tasks.**
  - `utils/trayRanking.js`, with a shared fixture that runs against both JS and Dart (7 cases). They
    agreed first time.
  - New columns `running_since` and `client_ref`.
  - The sweep skips running rows and caps them at 240 minutes.
- **QW-3 `c486c80` — `/api/quick`:** GET, start, done, stop, undo (`services/quickService.js`,
  `routes/quick.js`).
- **QW-4 — translations:** `srvErr*` entries for the ten new codes in all four ARB files.
- **Differences from §3:**
  - Every new key returns BIGINT ids as strings, like the rest of the API. The Swift client must
    decode `id` as a string.
  - "Done just now" returns the instance as `approved`. The sweep's `NOW()` is the transaction start,
    so the payout lands on the next sweep, usually the widget's next `GET /api/quick`.
- **Verified:**
  - `npm test` 406 passing; `flutter test` 329 passing.
  - On Postgres 16 in Docker: `db:init` ran twice, `check-admin-role` passed, and a live route smoke
    test (key auth, done, replay, start, a second start → 409, stop, undo with a revert, undo of a
    deletion, expired undo) ended with ledger sum = balance.

### Phase 2 (2026-10-23, agy QW-5 + QW-5b, reviewed by the lead)

- **Native:**
  - `ios/Runner/ExtensionsBridge.swift` is the `carecoins/extensions` channel, with the methods
    `isSupported`, `storeDeviceKey`, `status`, `refresh` and `clear`. It also activates `WCSession`.
  - `ios/Shared/DeviceKeyStore.swift` holds the keychain helpers, compiled into all four targets.
  - The team prefix comes from the Info.plist key `CareCoinsAppIdentifierPrefix`.
  - New `CareCoinsShared` constants: `snapshotFile`, `deviceKeyIdDefault` and `apiBaseDefault`.
- **Differences from §3.4:**
  - There is no `writeSnapshot`. The Dart side never holds the key after connecting, so Swift's
    `refresh` fetches `GET /api/quick` itself, writes `quick.json`, reloads timelines and calls
    `updateApplicationContext({deviceKey, apiBase, snapshot})`.
  - A 401 clears everything locally.
  - If the shared access group is refused, the keychain helpers fall back to the default group. On a
    simulator build without entitlements, the widget will not see the key.
- **Dart:**
  - `lib/services/extensions_bridge.dart` does nothing off iOS and coalesces refreshes.
  - Refresh runs after each successful Today `_load()` for caregivers, and after `fetchUserData`.
  - `logout()` calls `DELETE /api/me/device-keys`, then `clear`.
  - Me ▸ Widget & Watch is `lib/screens/devices_screen.dart`, for caregivers only.
  - The new `showConfirmDialog` in `widgets/ui.dart` now also backs `profile_screen`'s `_confirm`.
  - `formatShortDate` added to `utils/formatters.dart`.
- **Verified:** `flutter analyze` clean, `flutter test` 343 passing, and the simulator build succeeds.
  The live Connect flow on the simulator waits for the backend deploy (or a local backend).
