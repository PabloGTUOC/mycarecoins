# Graph Report - mycarecoins  (2026-10-05)

## Corpus Check
- 199 files · ~157,737 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1778 nodes · 2808 edges · 94 communities (84 shown, 10 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 66 edges (avg confidence: 0.89)
- Token cost: 78,957 input · 0 output

## Community Hubs (Navigation)
- Daily Screen Timeline
- Daily & Dashboard Data
- UI Kit Widgets
- App State & Session
- Onboarding Wizard
- Personal Time Sheet
- Flutter Test Suite
- Admin Registry & Retention
- Starter Activities Seeding
- Profile & Wallet
- Early SQL Migrations
- Purchases & API Client
- Stats Screen
- Landing Page
- Activities Screen
- Design Tokens
- Agent Guide Rules
- Marketplace Screen
- Admin Console Detail
- Backend Dependencies
- Timeline & Dashboard Cards
- Shell Navigation
- Charts & Painters
- Personal Time Service
- Coach Marks Tour
- Personal Area Actions
- Family Circle
- App Bootstrap & Auth Gate
- API Client Errors
- Activity Payouts & Ledger
- Membership & RBAC
- iOS Runner
- Testing Docs
- Admin & Subscriptions Plan
- Agent Guide Rules (2)
- Mobile UX Phase 1 Brief
- Daily Gesture & Week Strip
- Starter Packs Data
- Admin Screen Tabs
- Subscription Card
- Absence Dialog
- Validation & Transactions
- Express App Wiring
- Deployment Runbook
- Frontend Reference Docs
- Login Screen
- Avatar Upload
- Monthly Distribution
- Tour Service
- DB Init & Admin CLI
- Auth & Me Routes
- Billing Webhooks
- Schema Reference Docs
- Personal Time Design
- Legal Links
- Push Notify Helpers
- Design System Doc
- Activation Checklist
- Web Manifest
- Admin Auth Tests
- Deploy Script
- Setup Questionnaire Plan
- Help Sheet
- Onboarding Help Plan
- Firebase Options
- Test Suite Overview
- Absence Floor
- ARB Plural Test
- Running Instructions
- Setup Questionnaire Plan (2)
- Checklist Routes
- JSON Number Helpers
- Reward Redeem Confirmation
- Admin Family Navigation
- Android MainActivity
- Daily Screen Widget
- Task Sheet
- Cover Request Card
- Dashboard Screen Widget
- Onboarding Screen Widget
- Personal Time Sheet Widget
- Push Service Worker
- Email Validator
- Notification Preferences

## God Nodes (most connected - your core abstractions)
1. `AppState` - 112 edges
2. `users` - 30 edges
3. `assertActiveMember()` - 22 edges
4. `families` - 21 edges
5. `Backend Technical Reference` - 21 edges
6. `Mobile UX Proposal (Flutter app)` - 21 edges
7. `Platform Admin, Family Registry & Subscriptions Plan` - 19 edges
8. `Product — CareCoins` - 16 edges
9. `Express backend` - 16 edges
10. `withTransaction()` - 15 edges

## Surprising Connections (you probably didn't know these)
- `Guardrails from PRODUCT.md (no anxiety badges, coins not the point, declines invisible, colour not only signal)` --semantically_similar_to--> `Design system tokens (app_theme.dart)`  [INFERRED] [semantically similar]
  docs/mobile-ux-proposal.md → README.md
- `Backend tests with ordered mockClient` --rationale_for--> `Service layer returning {data}|{error}`  [INFERRED]
  CLAUDE.md → README.md
- `Admin screen (platform admin console)` --conceptually_related_to--> `Flutter admin console (Phase 5)`  [INFERRED]
  README.md → docs/admin-family-management-plan.md
- `adminService` --conceptually_related_to--> `Leak-prevention test (adminRegistry.test.js)`  [INFERRED]
  README.md → docs/admin-family-management-plan.md
- `entitlementService` --conceptually_related_to--> `Entitlement merge: most generous wins`  [INFERRED]
  README.md → docs/admin-family-management-plan.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Admin privacy boundary enforcement** — docs_admin_family_management_plan_landlord_not_housemate, docs_admin_family_management_plan_platform_role, docs_admin_family_management_plan_requireadmin, docs_admin_family_management_plan_leak_prevention_test, docs_admin_family_management_plan_admin_audit_log, readme_adminservice [EXTRACTED 1.00]
- **Docker Compose deployment chain** — docker_compose_postgres, docker_compose_db_init, docker_compose_backend, docker_compose_frontend [EXTRACTED 1.00]
- **Family entitlement pipeline (RevenueCat -> webhook -> family_plans -> entitlements)** — docs_admin_family_management_plan_revenuecat_flow, readme_billingservice, docs_admin_family_management_plan_subscription_data_model, docs_admin_family_management_plan_entitlement_merge, readme_entitlementservice, docs_admin_family_management_plan_readonly_suspension [EXTRACTED 1.00]
- **Mobile UX Phase 1 - Safety and access** — docs_mobile_ux_phase1_brief_t1_week_strip_gesture_split, docs_mobile_ux_phase1_brief_t2_redeem_confirm_sheet, docs_mobile_ux_phase1_brief_t3_ink_colours, docs_mobile_ux_phase1_brief_t4_semantics_labels, docs_mobile_ux_phase1_brief_t5_12pt_floor, docs_mobile_ux_proposal_p0_1_gesture_conflict, docs_mobile_ux_proposal_p0_2_redeem_confirmation, docs_mobile_ux_proposal_p0_3_contrast, docs_mobile_ux_proposal_p0_4_screen_readers, docs_mobile_ux_proposal_p1_5_small_text [EXTRACTED 1.00]
- **Onboarding help layers with telemetry** — docs_onboarding_help_plan_help_sheet, docs_onboarding_help_plan_coach_marks_tour, docs_onboarding_help_plan_activation_checklist, docs_onboarding_help_plan_telemetry_events, docs_database_schema_onboarding_events [EXTRACTED 1.00]
- **Coin ledger integrity guarantees** — claude_append_only_coin_ledger, readme_withtransaction, claude_ledger_reasons [INFERRED 0.85]
- **Personal time & coverage settlement model** — docs_personal_time_plan_activity_subclasses_care_self, docs_personal_time_plan_two_settlement_paths, docs_personal_time_plan_presence_weighted_residual, docs_personal_time_plan_counter_care_activity, docs_personal_time_plan_sweetener, docs_personal_time_handoff_createrequest, docs_personal_time_handoff_acceptrequest [INFERRED 0.85]
- **Subscription and store compliance** — fluterfront_pubspec_purchases_flutter, fluterfront_pubspec_url_launcher, fluterfront_web_privacy, fluterfront_web_terms [INFERRED 0.85]

## Communities (94 total, 10 thin omitted)

### Community 0 - "Daily Screen Timeline"
Cohesion: 0.03
Nodes (66): _absences, _activities, _activityEmoji, _buildChip, _buildDismissibleCard, _buildHourGrid, _buildNarrow, _buildWide (+58 more)

### Community 1 - "Daily & Dashboard Data"
Cohesion: 0.03
Nodes (65): daily_screen.dart, a, abs, _absences, _absencesOn, active, _activities, actor (+57 more)

### Community 2 - "UI Kit Widgets"
Cohesion: 0.03
Nodes (58): EdgeInsetsGeometry, accent, actionLabel, autofillHints, background, behavior, block, body (+50 more)

### Community 3 - "App State & Session"
Cohesion: 0.04
Nodes (51): dart:ui, dynamic get, actors, _afterSignIn, api, _authMessage, authReady, clearMessages (+43 more)

### Community 4 - "Onboarding Wizard"
Cohesion: 0.04
Nodes (50): ../data/starter_packs.dart, _acceptInvite, _alias, _areaIcons, _areas, build, _buildCreateWizard, _CareObjectEntry (+42 more)

### Community 5 - "Personal Time Sheet"
Cohesion: 0.04
Nodes (48): DateTime get, _balance, _baseline, build, _candidates, _conflicts, _coverageNeeded, _coverName (+40 more)

### Community 6 - "Flutter Test Suite"
Cohesion: 0.06
Nodes (37): AppLocalizations, _app, main, minAbsence, main, main, boundApp, main (+29 more)

### Community 7 - "Admin Registry & Retention"
Cohesion: 0.08
Nodes (28): main(), clearHeartbeatThrottle(), familyHeartbeat(), lastTouch, touchFamilyHeartbeat(), createGrant(), createPlan(), getFamilyBilling() (+20 more)

### Community 8 - "Starter Activities Seeding"
Cohesion: 0.08
Nodes (26): CHILD_ACTIVITIES, GENERIC_CARE_ACTIVITIES, HOUSEHOLD_ACTIVITIES, insertDefaultActivities(), insertStarterTasks(), PET_ACTIVITIES, STARTER_TYPES, validateStarterTasks() (+18 more)

### Community 9 - "Profile & Wallet"
Cohesion: 0.05
Nodes (42): admin_screen.dart, active, _alias, amount, balance, _changeMonth, _checkNotifPermission, _coinTier (+34 more)

### Community 10 - "Early SQL Migrations"
Cohesion: 0.11
Nodes (34): family_deletion_approvals, family_deletion_requests, fcm_tokens, notification_preferences, onboarding_events, personal_time_requests, admin_grants, billing_events (+26 more)

### Community 11 - "Purchases & API Client"
Cohesion: 0.05
Nodes (38): api_client.dart, _androidKey, _configured, _enabled, _ensureConfigured, entitlementId, hasProLocally, _iosKey (+30 more)

### Community 12 - "Stats Screen"
Cohesion: 0.05
Nodes (39): bool get, active, _BarRow, build, _buildCategoryBalance, _buildEconomy, _buildMembers, _buildOverview (+31 more)

### Community 13 - "Landing Page"
Cohesion: 0.05
Nodes (39): double?, accent, active, background, build, _buildHero, _check, child (+31 more)

### Community 14 - "Activities Screen"
Cohesion: 0.05
Nodes (38): dart:math, active, _activities, ActivitiesScreen, _ActivitiesScreenState, _approve, _budget, build (+30 more)

### Community 15 - "Design Tokens"
Cohesion: 0.05
Nodes (38): accentGradient, accents, accentSecondary, AppColors, AppRadii, base, bg, border (+30 more)

### Community 16 - "Agent Guide Rules"
Cohesion: 0.07
Nodes (36): CLAUDE.md (agent guide), Activity category + type model, Admins cannot see inside families, Append-only coin ledger, Every user-facing string in all four ARB files, Idempotent schema migrations chained in init-db.js, payoutReasons (db/ledgerReasons.js), Backend tests with ordered mockClient (+28 more)

### Community 17 - "Marketplace Screen"
Cohesion: 0.06
Nodes (35): DateTime, active, banner, _bannerColors, build, _buildCreate, _buildHistory, _buildStore (+27 more)

### Community 18 - "Admin Console Detail"
Cohesion: 0.06
Nodes (34): _billing, build, createState, d, dispose, _editPlan, _error, _eventsCard (+26 more)

### Community 19 - "Backend Dependencies"
Cohesion: 0.06
Nodes (33): dependencies, cors, dotenv, express, express-rate-limit, firebase-admin, multer, pg (+25 more)

### Community 20 - "Timeline & Dashboard Cards"
Cohesion: 0.06
Nodes (34): _ActivityAction, _TimelineCard, _AbsenceChip, _ActChip, _DayColumn, _DayHeader, _DayRow, _MemberCard (+26 more)

### Community 21 - "Shell Navigation"
Cohesion: 0.06
Nodes (31): activities_screen.dart, AppLifecycleListener, dashboard_screen.dart, active, build, createState, dispose, _go (+23 more)

### Community 22 - "Charts & Painters"
Cohesion: 0.07
Nodes (31): Color, CustomPainter, _GaugePainter, _FamilyFiguresPainter, build, color, DonutChart, _DonutPainter (+23 more)

### Community 23 - "Personal Time Service"
Cohesion: 0.15
Nodes (25): acceptRequest(), activeCaregivers(), baseRateFor(), cancelRequest(), conflictsFor(), createRequest(), declineRequest(), endOfDay() (+17 more)

### Community 24 - "Coach Marks Tour"
Cohesion: 0.07
Nodes (30): CoachMark get, _advance, body, build, CoachMark, _CoachOverlay, _CoachOverlayState, createState (+22 more)

### Community 25 - "Personal Area Actions"
Cohesion: 0.07
Nodes (29): _absenceDetail, _acceptBounty, build, _confirmSchedule, _load, _openBountyDialog, _openRecurrenceDialog, _openRequest (+21 more)

### Community 26 - "Family Circle"
Cohesion: 0.08
Nodes (26): _addActor, badge, build, _CircleCard, _copyLink, createState, FamilyCircle, _FamilyCircleState (+18 more)

### Community 27 - "App Bootstrap & Auth Gate"
Cohesion: 0.09
Nodes (24): firebase_options.dart, _appTheme, _AuthGate, _AuthGateState, build, CareCoinsApp, child, createState (+16 more)

### Community 28 - "API Client Errors"
Cohesion: 0.08
Nodes (23): dart:async, Exception, apiBase, ApiClient, ApiErrorKind, ApiException, delete, _headers (+15 more)

### Community 29 - "Activity Payouts & Ledger"
Cohesion: 0.16
Nodes (15): runAutoCompleteSweep(), ACTIVITY, COVERAGE, payoutReasons(), assertMemberRole(), acceptBounty(), approveActivity(), completeActivity() (+7 more)

### Community 30 - "Membership & RBAC"
Cohesion: 0.16
Nodes (16): assertActiveMember(), upsertUserFromAuth(), meetsRole(), requireRole(), ROLE_LEVELS, dashboardRouter, ALLOWED_MIME_TYPES, __dirname (+8 more)

### Community 31 - "iOS Runner"
Cohesion: 0.11
Nodes (14): Any, Bool, AppDelegate, SceneDelegate, RunnerTests, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge (+6 more)

### Community 32 - "Testing Docs"
Cohesion: 0.13
Nodes (20): node --test with mock DB clients, revertActivity appends reversal rows, Backend Technical Reference, activityService.js, assertFamilyWritable (402 on past_due), assertMemberRole, entitlementService.js, familyService.js (+12 more)

### Community 33 - "Admin & Subscriptions Plan"
Cohesion: 0.17
Nodes (19): admin_audit_log, Flutter admin console (Phase 5), Backend as single source of truth for entitlements, Double-purchase guard, Entitlement merge: most generous wins, Admin is the landlord, not a housemate, Leak-prevention test (adminRegistry.test.js), Orphaned families (out of scope) (+11 more)

### Community 34 - "Agent Guide Rules (2)"
Cohesion: 0.16
Nodes (19): Family heartbeat (last_active_at), Read-only suspension gate (past_due -> 402), absenceService (24h floor), activityService, adminService, Express backend, billingService, distributionService (presence-weighted GDP residual) (+11 more)

### Community 35 - "Mobile UX Phase 1 Brief"
Cohesion: 0.15
Nodes (18): Mobile UX Phase 1 Implementation Brief, Phase 1 ground rules (branch, one commit per ticket, no dart format, 4 ARB files, Flutter only), T2 Confirm before redeeming a reward, T3 Readable pill and card colours, T4 Screen-reader labels, T5 12 pt text floor, Ink tokens (warningInk, successInk, primaryInk, dangerInk), P0-3 Action pill colour contrast failures (+10 more)

### Community 36 - "Daily Gesture & Week Strip"
Cohesion: 0.16
Nodes (18): Daily Gesture & Week Stripe-to-remove, D1 Tab set: Today, Family, Tasks, Rewards, Me, D2 Needs-you indicator is a dot only, D3 Checklist step completes on first payout, D4 Dark mode after token migration, P0-1 Swipe changes day and deletes card, P1-1 Daily screen as Today tab, P1-2 Needs you block (+10 more)

### Community 37 - "Starter Packs Data"
Cohesion: 0.11
Nodes (17): areas, areasForDependents, durationMinutes, isRecurrent, kUniversalAreas, StarterArea, starterAreaLabel, starterEntries (+9 more)

### Community 38 - "Admin Screen Tabs"
Cohesion: 0.16
Nodes (18): AdminFamilyDetailScreen, _AdminFamilyDetailScreenState, AdminScreen, _AdminScreenState, _FamiliesTab, _FamiliesTabState, _PlansTab, _PlansTabState (+10 more)

### Community 39 - "Subscription Card"
Cohesion: 0.12
Nodes (17): build, _busy, createState, _ent, _familyId, initState, _load, _loading (+9 more)

### Community 40 - "Absence Dialog"
Cohesion: 0.12
Nodes (16): @visibleForTesting, absenceWindowFromRange, anchor, app, confirmed, firstDate, l, lastDate (+8 more)

### Community 41 - "Validation & Transactions"
Cohesion: 0.40
Nodes (10): withTransaction(), isoDate(), oneOf(), positiveInt(), required(), string(), validateBody(), validateParams() (+2 more)

### Community 42 - "Express App Wiring"
Cohesion: 0.14
Nodes (13): adminLimiter, ALLOWED_ORIGINS, app, __dirname, __filename, perUserLimiter, absencesRouter, activitiesRouter (+5 more)

### Community 43 - "Deployment Runbook"
Cohesion: 0.12
Nodes (16): billingService.js, Deployment and Delivery, Android delivery, iOS delivery, Every release, in order, Rollback, Server deploy & verify, Third-party consoles (Firebase, RevenueCat, Apple, Google Play) (+8 more)

### Community 44 - "Frontend Reference Docs"
Cohesion: 0.16
Nodes (16): users, Flutter Frontend Technical Reference, Bootstrap and the auth gate, Legal documents (terms/privacy), Navigation shell, Fairness surfacing (Phase 7), Product — CareCoins, provider + single AppState (+8 more)

### Community 45 - "Login Screen"
Cohesion: 0.14
Nodes (14): build, createState, dispose, _email, _forgotPassword, _google, _GoogleMark, _isRegistering (+6 more)

### Community 46 - "Avatar Upload"
Cohesion: 0.13
Nodes (14): app, bytes, _jpeg, mime, null, pickAndUploadAvatar, picked, _png (+6 more)

### Community 47 - "Monthly Distribution"
Cohesion: 0.22
Nodes (10): distributionShares(), nextMonth(), presentHours(), runMonthlyDistribution(), settleMonth(), AUG, fullTime, JUL_END (+2 more)

### Community 48 - "Tour Service"
Cohesion: 0.14
Nodes (13): ChangeNotifier, hasSeen, I, _key, markSeen, resetTabTours, shouldShow, suppressAll (+5 more)

### Community 49 - "DB Init & Admin CLI"
Cohesion: 0.19
Nodes (6): __dirname, __filename, pool, __dirname, __filename, logLoginHistory()

### Community 50 - "Auth & Me Routes"
Cohesion: 0.19
Nodes (11): deleteFirebaseUser(), getFirebaseApp(), requireAuth(), email(), ALLOWED_MIME_TYPES, DEFAULT_PREFS, __dirname, __filename (+3 more)

### Community 51 - "Billing Webhooks"
Cohesion: 0.19
Nodes (7): attributedFamilyId(), ENTITLEMENT_PLAN_MAP, planCodeFor(), PLATFORM_BY_STORE, processWebhookEvent(), STATUS_BY_EVENT, baseEvent

### Community 52 - "Schema Reference Docs"
Cohesion: 0.15
Nodes (13): FCM push notifications, Database Schema Reference, absences, activities, families, family_members, fcm_tokens, marketplace_rewards (+5 more)

### Community 53 - "Personal Time Design"
Cohesion: 0.23
Nodes (13): personal_time_requests, Personal Time & Coverage Handoff, acceptRequest, Ask anyone, createRequest, Recurrence & expiry (Phase 6), Activity Subclasses, Personal Time & Coverage Plan, Absence floor (Phase 1) (+5 more)

### Community 54 - "Legal Links"
Cohesion: 0.15
Nodes (12): app, build, kPrivacyPolicyUrl, kTermsOfUseUrl, l, label, _LegalLink, LegalLinks (+4 more)

### Community 55 - "Push Notify Helpers"
Cohesion: 0.40
Nodes (10): announce(), when(), getMessaging(), notifyFamilyAll(), notifyFamilyCaregivers(), notifyUser(), prefClause(), pruneStale() (+2 more)

### Community 56 - "Design System Doc"
Cohesion: 0.24
Nodes (11): Design System: CareCoins, Daily Timeline (signature component), The Family Operations Room (creative north star), The Flat-By-Default Rule, MEMBER_THEMES assignee colors, NOW divider, The One Job Rule (color semantics), The Operations Palette (+3 more)

### Community 57 - "Activation Checklist"
Cohesion: 0.18
Nodes (10): ActivationChecklist, build, ChecklistStep, done, label, onDismiss, onGo, steps (+2 more)

### Community 58 - "Web Manifest"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 59 - "Admin Auth Tests"
Cohesion: 0.28
Nodes (5): checkPlatformAdmin(), requireAdmin(), auth, run(), userRow

### Community 60 - "Deploy Script"
Cohesion: 0.42
Nodes (8): die(), ok(), remote(), remote_read(), deploy.sh script, step(), usage(), warn()

### Community 61 - "Setup Questionnaire Plan"
Cohesion: 0.25
Nodes (8): CareCoins Automated Test Suite, Missing E2E layer (integration_test + emulator), Flutter unit and widget tests, Localization (ARB / gen-l10n), Internationalization Plan, Keep languages aligned (guardrails), flutter_localizations + ARB + gen-l10n, User language selection

### Community 62 - "Help Sheet"
Cohesion: 0.25
Nodes (7): build, _HelpContent, _HelpSectionTitle, showHelpSheet, text, ../services/tour_service.dart, ../theme/app_theme.dart

### Community 63 - "Onboarding Help Plan"
Cohesion: 0.33
Nodes (7): onboarding_events, Onboarding, tours and telemetry, Onboarding & In-App Help Plan, Activation checklist, First-run guided tour (coach marks, tour_service), How CareCoins works help sheet + glossary, Telemetry → POST /api/events

### Community 64 - "Firebase Options"
Cohesion: 0.29
Nodes (6): android, DefaultFirebaseOptions, ios, web, package:firebase_core/firebase_core.dart, static const FirebaseOptions

### Community 65 - "Test Suite Overview"
Cohesion: 0.29
Nodes (7): Test Suite Overview, no E2E), CareCoins Architecture & System Description, utils/notify.js FCM helpers, Privacy boundary: admin is landlord not housemate, Push notifications (FCM), rbac middleware (requireRole / requireAdmin), Starter tasks catalogue (client-side)

### Community 66 - "Absence Floor"
Cohesion: 0.47
Nodes (3): MIN_ABSENCE_HOURS, validateAbsenceWindow(), base

### Community 67 - "ARB Plural Test"
Cohesion: 0.33
Nodes (5): dart:convert, dart:io, File, arbs, main

### Community 68 - "Running Instructions"
Cohesion: 0.33
Nodes (6): CORS policy (exact origins), API communication (api_client), Running Instructions, API_BASE dart-define, Development mode (backend + flutter run), Production Docker mode

### Community 69 - "Setup Questionnaire Plan (2)"
Cohesion: 0.53
Nodes (6): Family Setup Questionnaire Plan, Activity-areas questionnaire step, Blind seeding problem, defaultActivities.js / insertDefaultActivities, Client-side localized starter packs, starterTasks API contract

### Community 70 - "Checklist Routes"
Cohesion: 0.33
Nodes (6): _buildChecklist, Route complete, Route create_task, Route reward, Route schedule, Route validate

### Community 71 - "JSON Number Helpers"
Cohesion: 0.33
Nodes (5): fallback, null, toNum, toNumOrNull, return

### Community 72 - "Reward Redeem Confirmation"
Cohesion: 0.50
Nodes (4): P0-2 Redeem reward without confirmation, Activity lifecycle, autoComplete.js sweep, coin_ledger table

### Community 73 - "Admin Family Navigation"
Cohesion: 0.50
Nodes (4): _familyRow, _openDaily, _buildAccountCard, MaterialPageRoute

## Ambiguous Edges - Review These
- `onboarding_events` → `Activity-areas questionnaire step`  [AMBIGUOUS]
  docs/family-setup-questionnaire-plan.md · relation: conceptually_related_to

## Knowledge Gaps
- **882 isolated node(s):** `name`, `version`, `description`, `main`, `type` (+877 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `onboarding_events` and `Activity-areas questionnaire step`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `AppState` connect `Personal Area Actions` to `Daily Screen Timeline`, `Daily & Dashboard Data`, `UI Kit Widgets`, `App State & Session`, `Onboarding Wizard`, `Personal Time Sheet`, `Profile & Wallet`, `Stats Screen`, `Activities Screen`, `Marketplace Screen`, `Admin Console Detail`, `Timeline & Dashboard Cards`, `Shell Navigation`, `Family Circle`, `App Bootstrap & Auth Gate`, `Admin Screen Tabs`, `Subscription Card`, `Absence Dialog`, `Login Screen`, `Avatar Upload`, `Tour Service`, `Legal Links`, `Admin Family Navigation`, `Daily Screen Widget`, `Cover Request Card`, `Dashboard Screen Widget`, `Onboarding Screen Widget`, `Personal Time Sheet Widget`?**
  _High betweenness centrality (0.060) - this node is a cross-community bridge._
- **Why does `_buildChecklist` connect `Checklist Routes` to `Daily & Dashboard Data`?**
  _High betweenness centrality (0.008) - this node is a cross-community bridge._
- **Why does `assertActiveMember()` connect `Membership & RBAC` to `Starter Activities Seeding`, `Validation & Transactions`, `Auth & Me Routes`, `Personal Time Service`, `Activity Payouts & Ledger`?**
  _High betweenness centrality (0.004) - this node is a cross-community bridge._
- **What connects `name`, `version`, `description` to the rest of the system?**
  _882 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Daily Screen Timeline` be split into smaller, more focused modules?**
  _Cohesion score 0.029850746268656716 - nodes in this community are weakly interconnected._
- **Should `Daily & Dashboard Data` be split into smaller, more focused modules?**
  _Cohesion score 0.030303030303030304 - nodes in this community are weakly interconnected._