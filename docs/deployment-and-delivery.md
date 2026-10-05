# Deployment and Delivery — CareCoins

The complete path from this repo to users: the server, the two store apps, and the
third-party consoles that have to agree with them. Written to be followed top to bottom by
someone with no other context.

Replaces the former `docs/deployment.md` and `docs/store-release-checklist.md`, which
described overlapping ground and had drifted apart.

```
                        ┌─▶ 1. Server (web app + API)   docker compose, ~10 min
git push origin main ───┼─▶ 2. iOS app                  TestFlight → App Store
                        └─▶ 3. Android app              internal track → Play
```

**Deploy the server first.** Both store builds bake in `https://mycarecoins.app`, so an app
shipped ahead of the server talks to an API that lacks its endpoints.

---

## Table of Contents

1. [Where things stand](#1-where-things-stand)
2. [Server](#2-server)
3. [Third-party consoles](#3-third-party-consoles) — Firebase, RevenueCat, Apple, Google
4. [iOS delivery](#4-ios-delivery)
5. [Android delivery](#5-android-delivery)
6. [Store listings and paperwork](#6-store-listings-and-paperwork)
7. [Every release, in order](#7-every-release-in-order)
8. [Post-launch verification](#8-post-launch-verification)
9. [Rollback](#9-rollback)

---

## 1. Where things stand

`main` serves the Flutter frontend (`fluterFront/`) — the only frontend.

**Production is well behind `main`.** Probed on 2026-08-28: `/api/personal-time`,
`/api/admin/*` and `/api/billing/webhook` all return **404**, meaning the deployed backend
predates personal time, the admin console and billing. `/api/me`, `/api/activities`,
`/api/absences` and `/api/events` return 401, so those exist. The *frontend* container was
rebuilt at some point; the backend was not.

Practical consequences until [§2](#2-server) is done:

- Every personal-time feature 404s in the app.
- The RevenueCat webhook points at `/api/billing/webhook`, which does not exist — **no
  purchase can upgrade a family**.
- Seven migrations are pending: `absence-floor`, `activity-subclasses`, `heartbeat`,
  `ledger-reversals`, `personal-time`, `plans`, `platform-admin`.

Repeat the probe any time you want to know what is actually deployed — an unmounted route
falls through to the 404 handler, a mounted one answers 401:

```bash
for p in /api/me /api/personal-time /api/admin/families; do
  printf "%-28s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' https://mycarecoins.app$p)"
done
# /api/billing/webhook is POST-only — a GET returns 404 either way, so it has to
# be asked properly. 401 = mounted and it rejected the body; 404 = not deployed.
curl -s -o /dev/null -w 'billing %{http_code}\n' -X POST \
     -H 'Content-Type: application/json' -d '{}' \
     https://mycarecoins.app/api/billing/webhook
```

---

## 2. Server

Production is one Docker Compose stack behind Cloudflare:

```
Cloudflare (HTTPS) → nginx :80 (frontend container) → backend:3000 + postgres
```

The nginx container serves the Flutter **web build** and proxies `/api` and `/uploads` to the
backend. The native apps use that same public gateway, so nothing extra is ever exposed for
them.

### Before the first deploy after a long gap

**Back the database up, and rehearse on the copy.** This deploy runs seven migrations against
real data:

```bash
docker compose exec -T postgres pg_dump -U <user> <db> > backup-$(date +%F).sql
```

The one to watch is **`migrate-activity-subclasses.sql`**: it renames `category` → `type` and
adds a new `category`, rewriting existing activity rows. It is the only migration here that
touches existing rows rather than adding to them. (`migrate-ledger-reversals.sql`, added after
the rehearsal below, only *inserts* — the credits that old reverts overwrote.)

**This upgrade has been rehearsed** (2026-08-28), not just reasoned about. The schema production
actually runs was rebuilt on Postgres 16 from the backend it was deployed with, seeded
with representative data — twelve activities across both old categories, templates and
instances, four statuses, plus ledger rows, balances, an absence, a reward and an actor — and
then upgraded with the current `db:init`. Results:

| | Before | After |
|---|---|---|
| activities | 12 (care 8, household 4) | 12 (all `category='care'`; `type` care 8 / household 4) |
| templates | 3 | 3 |
| ledger sum | 50 | 50 |
| balances | Ana=320, Ben=145 | unchanged |
| absences · rewards · actors | 1 · 1 · 1 | unchanged |

Nothing was lost, the old `category` became `type` exactly as intended, a second `db:init`
changed nothing further, and the compound CHECK then correctly rejected both `self` +
`coverage` and a `self` activity carrying coins. The new backend starts against the upgraded
database with no errors and every route mounted.

### Deploy

**Scripted, from your machine** — this is the normal path:

```bash
cp scripts/deploy.env.example scripts/deploy.env   # once: name your server
./scripts/deploy.sh --dry-run                      # see every step, change nothing
./scripts/deploy.sh                                # deploy, with one confirmation
```

`scripts/deploy.sh` refuses to run unless your tree is clean and pushed, backs up the database
*and* the uploads directory before touching anything, copies the two gitignored secrets, then
fast-forwards the server and rebuilds. It finishes by probing the public API and prints the
exact rollback command for the commit it replaced. It uses your normal SSH key; `deploy.env`
holds no passwords and is gitignored because it names your server.

#### Starting from an empty database

```bash
./scripts/deploy.sh --reset-db                   # wipe, then deploy
./scripts/deploy.sh --reset-db --reset-uploads   # also clear stored avatars
```

`--reset-db` runs `docker compose down -v` before the rebuild. The compose file declares
exactly one named volume, `pgdata`, so that drops the Postgres data directory and nothing
else; `db-init` then migrates a fresh, empty cluster on the next start.

It is deliberately awkward, because it destroys every family, activity and coin balance and
cannot be undone:

- it forces a backup, and **refuses to run at all** with `--skip-backup`;
- it asks you to type the host name, not `y` — and `--yes` does not bypass that;
- it verifies the result rather than the exit code: `families` must be 0 and
  `personal_time_requests` must exist, which together prove the volume really was dropped and
  the migrations really did run.

Two things it does **not** do, both stated at the prompt:

- **Firebase accounts survive.** Everyone can still sign in, and lands on the create-a-family
  wizard as a new user. Whoever signs in first should create the family and invite the rest.
- **Avatars survive**, because `backend/uploads` is a bind mount rather than a volume. They
  become orphaned files pointing at rows that no longer exist. `--reset-uploads` clears them.

**By hand**, if you would rather, or to debug the script:

```bash
git pull
docker compose up --build -d      # rebuilds the frontend image, restarts the stack
docker compose ps                 # everything Up; db-init exits 0 (that is normal)
```

Notes:

- `db-init` applies `schema.sql` plus every `backend/scripts/migrate-*.sql` on each start,
  idempotently. Nothing to run by hand.
- `firebase-credentials.json` must sit next to `docker-compose.yml`. It is gitignored and is
  **not** in the repo — copy it to the server out of band.
- `backend/.env` on the server needs `REVENUECAT_WEBHOOK_SECRET` (see
  [§3.2](#32-revenuecat)). Restart the backend after changing it.
- The old `VITE_*` variables are dead; the Flutter web app compiles its Firebase config in.

### Verify

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://mycarecoins.app/api/personal-time   # want 401, not 404
curl -s -o /dev/null -w '%{http_code}\n' https://mycarecoins.app/privacy             # want 200
```

Then in a browser at https://mycarecoins.app: landing page renders → email sign-in → Google
sign-in → an avatar image loads (proves `/uploads` proxying) → enable push notifications
(proves the `firebase-messaging-sw.js` service worker).

---

## 3. Third-party consoles

Four consoles have to agree with the code. Do Firebase and RevenueCat first — the store
submissions depend on them.

### 3.1 Firebase

| Step | Why it matters |
|---|---|
| Upload an **APNs auth key** (.p8) under Project settings → Cloud Messaging → Apple app configuration | Without it, FCM silently never delivers to iOS |
| Register **two Android SHA-1s**: the upload keystore's *and* the Play App Signing one (Play Console → Setup → App integrity), then re-download `google-services.json` into `fluterFront/android/app/` | Missing fingerprints give Google Sign-In **error code 10** in production while debug works fine |
| Confirm `mycarecoins.app` is in Authentication → Authorized domains | Web sign-in fails without it |

Get the upload keystore's fingerprint with:

```bash
keytool -list -v -keystore ~/carecoins-upload.jks
# keytool lives at /Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool
```

### 3.2 RevenueCat

Already configured against a **Test Store** as of 2026-08-03 — products (`monthly`, `yearly`,
`lifetime`), the `MyCareCoins Pro` entitlement, the default offering, a built paywall with a
Restore · Terms · Privacy footer, and Customer Center. Full record: `docs/RevenueCatSetup.md`.

Remaining for a real release:

- [ ] Add the **real App Store and Play Store apps** to the project with store credentials,
      then copy the `appl_…` and `goog_…` **public** SDK keys.
- [ ] Recreate the three products in App Store Connect and Play Console with **identical
      product IDs**, import them, attach them to the same entitlement and offering.
- [ ] **Rotate the webhook secret.** The value in `docs/RevenueCatSetup.md` is the sandbox
      one and is in the repo — fine for a fake store, not for real money. New random value →
      webhook Authorization header → `backend/.env` → restart the backend. Do not record the
      production value anywhere.
- [ ] Point the paywall footer's Terms and Privacy links at `https://mycarecoins.app/terms`
      and `/privacy`.
- [ ] Verify the webhook with the dashboard's *send test event*: expect **200**. A 401 means
      the header and `REVENUECAT_WEBHOOK_SECRET` differ; a 404 means the server has not been
      deployed yet ([§2](#2-server)).

The entitlement identifier is `MyCareCoins Pro`, exactly — including the space. It is
load-bearing in `PurchaseService.entitlementId` and in `billingService.js`'s entitlement →
plan mapping. A typo makes every entitlement check quietly return false.

**Once you have the two SDK keys**, put them in `lib/services/purchase_service.dart` as the
defaults, replacing the test-store fallback. They are public keys, safe to embed, and the
repo already commits this class of config (`firebase_options.dart`, `google-services.json`,
`GoogleService-Info.plist`). Leaving the test key as the default means a release built without
`--dart-define` installs, runs, shows a paywall and **sells nothing**, with no warning
anywhere.

### 3.3 Apple

1. **Apple Developer Program** membership ($99/yr). Start here — enrolment approval is the
   long pole, especially for an organisation needing a D-U-N-S number.
2. Register the App ID `com.carecoins.carecoinsFlutter` with the **Push Notifications**
   capability.
3. Create an **APNs auth key** under Keys, and upload it to Firebase ([§3.1](#31-firebase)).
4. In Xcode (`fluterFront/ios/Runner.xcworkspace`) → Signing & Capabilities → select your
   Team → **+ Capability → Push Notifications**. `UIBackgroundModes: remote-notification` is
   already in `Info.plist`.
5. **App Store Connect** → create the app record with the same bundle ID, then add the three
   subscription products with the IDs from [§3.2](#32-revenuecat).

Two smaller items worth handling before the first upload:

- There is no app-level `PrivacyInfo.xcprivacy` (only the Pods ship theirs). Expect
  `ITMS-91053` "missing API declaration" warnings by email.
- `ITSAppUsesNonExemptEncryption` is absent from `Info.plist`, so every upload re-asks the
  export-compliance question. Adding `<false/>` settles it permanently.

### 3.4 Google Play

1. **Play Console** account ($25, one-time).
2. Create the app and **enrol in Play App Signing**.
3. Create the three subscription products with the same IDs.
4. Register the Play App Signing SHA-1 in Firebase ([§3.1](#31-firebase)).

---

## 4. iOS delivery

```bash
cd fluterFront
# bump version: x.y.z+N in pubspec.yaml — N must increase on every upload
flutter build ipa --dart-define=API_BASE=https://mycarecoins.app \
                  --dart-define=RC_IOS_KEY=appl_…
```

Upload `build/ios/ipa/*.ipa` with Xcode Organizer or Transporter. It appears in **TestFlight**
— distribute to internal testers with no review. For the public store, submit for review
**with a demo account in the review notes**: reviewers cannot join a family without an invite,
and would otherwise be stuck at onboarding.

ATS is store-safe: iOS ships `NSAllowsLocalNetworking` with no `NSAllowsArbitraryLoads`.

> **`build` must stay symlinked outside iCloud.** The repo lives in iCloud Drive and
> `codesign` rejects the `FinderInfo` xattrs iCloud attaches. `fluterFront/build` is a symlink
> to `~/flutter-builds/carecoins`; keep it that way.

---

## 5. Android delivery

One-time, before the first build:

1. **Create an upload keystore** and back it up. Losing it before Play App Signing is enrolled
   means never being able to update the app under the same listing.

   ```bash
   keytool -genkey -v -keystore ~/carecoins-upload.jks -alias upload \
           -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Copy `fluterFront/android/key.properties.example` to `android/key.properties` and fill in
   the four values. Use an **absolute** `storeFile` path — `~` is not expanded, and a relative
   path resolves against `fluterFront/android/`. The file is gitignored; never commit it.

3. Confirm the wiring:

   ```bash
   cd fluterFront/android && ./gradlew :app:signingReport
   # under "Variant: release" you want "Config: release" and your keystore path
   ```

The `signingConfigs.release` block is already wired in `android/app/build.gradle.kts`. Without
`key.properties`, **`flutter build appbundle` fails outright** with instructions — an `.aab`
exists only to be uploaded, and Play rejects debug-signed uploads, so producing one is never
useful. `flutter run --release` and `flutter build apk` still fall back to debug signing (with
a warning) so local release testing keeps working.

```bash
cd fluterFront
flutter build appbundle --dart-define=API_BASE=https://mycarecoins.app \
                        --dart-define=RC_ANDROID_KEY=goog_…
```

Upload `build/app/outputs/bundle/release/app-release.aab` in Play Console → **Internal
testing** first, then promote. Cleartext HTTP is debug-only: `usesCleartextTraffic` lives
solely in the debug manifest.

---

## 6. Store listings and paperwork

**Legal pages — done in code, not yet in content:**

- [x] `fluterFront/web/privacy.html` and `terms.html` ship with the web build; `nginx.conf`
      maps `/privacy` and `/terms` to them.
- [x] Both are linked inside the app, in Personal Area under the subscription card
      (`lib/utils/legal_links.dart`). Apple requires this for auto-renewable subscriptions
      (Guideline 3.1.2).
- [ ] **Fill in the bracketed placeholders in both pages** — legal entity, contact email,
      hosting location, retention period, jurisdiction — and have them reviewed. They are
      drafts: the factual sections were written from the real database schema, but the legal
      framing is not advice. Apple's [standard EULA][eula] is an accepted substitute if you
      would rather not maintain your own.
- [ ] Confirm both URLs load in a plain browser on the live domain, then paste the privacy URL
      into both store listings.

[eula]: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

**Both stores:**

- [ ] Data-safety / privacy-nutrition forms: account data (email, name, avatar), user content
      (tasks, rewards), device token for push. No ads, no tracking SDKs.
- [ ] Screenshots: iPhone 6.7", iPad 13", Android phone and 10" tablet — the simulators and
      emulators used in development produce all four.
- [x] App icon ships in the builds (generated from `assets/icon/icon-512.png`; regenerate with
      `dart run flutter_launcher_icons`).

**Subscriptions are active in the app**, so these are first-submission requirements, not
preparation:

- [ ] Products exist in both stores with matching IDs, attached to the RevenueCat entitlement.
- [x] **Restore purchases** entry point exists — Apple requires it. Entitlements are
      authoritative on the backend, so restore is a re-sync, but the button must be there.
- [ ] Paywall shows price, billing period and auto-renewal terms before purchase. Both stores
      reject paywalls that hide the renewal.
- [ ] "Manage subscription" deep-links to the store's own settings. Never cancel server-side —
      the payment relationship belongs to the user and the store.
- [ ] Double-purchase guard: a family already subscribed on the other platform sees "manage it
      there" rather than a second checkout.
- [ ] Sandbox matrix on both stores: purchase, renewal, cancel, expiration, billing-issue and
      grace, plus cross-platform visibility (iOS sandbox purchase → Android member sees Pro).
- [ ] Listing metadata declares the subscription (App Store "In-App Purchases" / Play
      "In-app products").

---

## 7. Every release, in order

1. [ ] `git pull` and confirm the working tree is clean.
2. [ ] Bump `version:` in `fluterFront/pubspec.yaml` — `x.y.z+N`, and **N must increase on
       every upload**. Currently `1.0.0+1`.
3. [ ] `cd backend && npm test` — clean.
4. [ ] `cd fluterFront && flutter analyze && flutter test` — clean, and `untranslated.json`
       empty.
5. [ ] **Deploy the server** ([§2](#2-server)), and verify with the probe.
6. [ ] Smoke-test a release build on a real device:
       `flutter run --release --dart-define=API_BASE=https://mycarecoins.app` — email login,
       Google login, create and validate a task, avatar upload, push notification.
7. [ ] Build and upload iOS ([§4](#4-ios-delivery)) and Android ([§5](#5-android-delivery)),
       both with their RevenueCat keys.
8. [ ] TestFlight / internal track pass before promoting.

---

## 8. Post-launch verification

On a real device, installed from TestFlight or the internal track — not the simulator, which
has no APNs and no StoreKit products:

- [ ] Google sign-in works (validates the SHA-1 and reversed-client-id wiring).
- [ ] A push arrives with the app backgrounded (validates the APNs key and the FCM path).
- [ ] Avatar upload succeeds (validates `/uploads` proxying through nginx).
- [ ] A sandbox purchase flips the family to Pro within seconds (validates paywall →
      RevenueCat → webhook → `family_plans` → entitlements). If it never flips, the backend log
      shows a 401 for a secret mismatch, or a "no family_id attribute" warning.
- [ ] After the first cohort, run `backend/scripts/onboarding-report.sql` against production to
      measure activation (`docs/onboarding-help-plan.md`, phase 4).

---

## 9. Rollback

**Never to a commit older than the database.** Migrations only move forward: a backend from
before `migrate-activity-subclasses.sql` runs against a database where `activities.category`
and `.type` are `NOT NULL`, and every activity insert fails.

Roll back to an earlier `main` commit that already knows the current schema:

```bash
git checkout <last-known-good-sha> && docker compose up --build -d
```

Migrations are additive and idempotent, so an earlier `main` runs against the current
database — but check the commit you pick is not older than a migration whose columns its code
requires. If the schema itself has to come back, restore the dump taken in
[§2](#before-the-first-deploy-after-a-long-gap).

---

**See also:** `docs/RevenueCatSetup.md` (dashboard configuration record),
`docs/flutter-frontend.md` (build defines, local stack, platform gotchas),
`docs/backend.md` (API and services), `docs/database-schema.md` (columns and migrations).
