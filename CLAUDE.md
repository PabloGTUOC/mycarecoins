# CareCoins

Family caregiving app: a coin economy makes household and care work visible and fairly
shared. `docs/PRODUCT.md` is the product brief; `README.md` is the architecture overview.

## Layout

| Path | What |
|---|---|
| `backend/` | Node 20 + Express 4 REST API, PostgreSQL 16, Firebase Admin (auth + FCM) |
| `backend/src/routes/` → `services/` | Routes validate and authorize; business logic lives in services that take a `client` |
| `backend/src/db/schema.sql` + `backend/scripts/migrate-*.sql` | Schema; migrations chained in `scripts/init-db.js` |
| `fluterFront/` | Flutter app — the only frontend — for web, iOS and Android (`provider` + one `AppState`) |
| `fluterFront/lib/l10n/` | ARB files: en (template), es, fr, de |
| `scripts/deploy.sh` | Production deploy over SSH (`--dry-run` first) |
| `docs/` | Design docs and implementation logs |
| `graphify-out/` | Code knowledge graph — use the `graphify` skill to query it |

## Commands

```bash
cd backend && npm test                              # unit tests, mock DB clients, no database needed
cd backend && npm run dev                           # API on :3000
cd backend && npm run dev:test                      # API against the Firebase Auth emulator
cd backend && npm run db:init                       # schema + every migration; must stay re-runnable
cd fluterFront && flutter analyze && flutter test   # both must be clean
cd fluterFront && flutter run -d chrome
```

To check a migration against real Postgres, follow `docs/automatic-testing-E2E.md` § How to run.
Run `db:init` twice.

## Rules that are easy to break

- **The coin ledger is append-only.** Never `UPDATE` or `DELETE` a `coin_ledger` row. To undo,
  insert a reversal row (`*_reverted`). Every balance change pairs a `family_members.coin_balance`
  update with a ledger row in the same transaction, so `SUM(amount)` always equals the balances.
- **The economy has two layers.** Explicit activity payouts *and* the monthly residual
  (`distributionService.js`). Logging an activity does not create coins: it moves them from the
  residual to whoever did the work. Do not reason about coin flow from `activityService.js`
  alone. The real monthly ceiling is `totalGdp`, not `families.monthly_coin_budget`.
- **Activities are `category` + `type`, both `NOT NULL`.** `care` → `care | household | coverage`;
  `self` → `sport | social | rest | appointment | other`, always worth 0 coins. `coverage` is
  written only by the personal-time accept flow, and it is the one type allowed to overlap.
- **Payout reasons come from `db/ledgerReasons.js`** (`payoutReasons(type)`). Coverage files under
  its own reasons, so never hard-code `activity_completed` / `bounty_earned`.
- **Personal-time declines are never counted or shown anywhere.** That is a product decision
  (`docs/PRODUCT.md` §15), not an omission.
- **Admins cannot see inside families.** `/api/admin/*` returns liveness and billing only, never
  members, activities, coins or rewards, and a test enforces it. Admin is granted only via
  `node backend/scripts/promote-admin.js <email>`. Every admin mutation writes `admin_audit_log`
  in the same transaction.
- **Schema changes:** add an idempotent `backend/scripts/migrate-<name>.sql`, mirror it in
  `schema.sql`, and chain it in `init-db.js`. Production runs `db:init` on every container start.
- **Authorization lives server-side.** Use `requireRole` / `requireAdmin` (`middleware/rbac.js`)
  or the service-level membership check. UI gating is cosmetic.
- **Every user-facing string goes in all four ARB files.** No literals in widgets. ICU plurals
  must not contain a bare `#` (`arb_plurals_test.dart`).
- **Don't run `dart format` on whole files.** The code is not formatter-clean, and it turns a
  small edit into a diff of hundreds of lines. Match the surrounding style by hand.
- **Backend tests use `mockClient`,** which answers queries in order. When a service gains or
  loses a query, update the response list in the test.

## Docs to trust

- Current references: `docs/backend.md`, `docs/flutter-frontend.md`, `docs/database-schema.md`,
  `docs/DESIGN.md`.
- `docs/deployment-and-delivery.md` is the release runbook and records what is actually deployed.
  Production lags `main`, so check it before assuming a route exists live.
- The `*-plan.md` files carry a status line and per-phase **As built** logs.
- `fluterFront/MOBILE_AUDIT.md` and `docs/personal-time-handoff.md` are dated snapshots. Verify
  anything in them against the code before acting on it.
