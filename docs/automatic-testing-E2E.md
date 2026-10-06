# CareCoins — Automated Test Suite

## Overview

| Layer | Runner | Tests | Command |
|---|---|---|---|
| Backend unit | Node `--test` (built-in) | **212** | `cd backend && npm test` |
| Flutter unit + widget | `flutter test` | **59** | `cd fluterFront && flutter test` |
| Static analysis | `flutter analyze` | — | `cd fluterFront && flutter analyze` |
| End-to-end | — | **none** | — |

Backend tests use mock DB clients and need no database. Migrations and the
money-moving paths are additionally verified by hand against a throwaway Postgres 16
container — see `docs/personal-time-plan.md` for the pattern, including a two-session run
driving the real HTTP API with users minted from the Firebase Auth emulator.

**The gap:** there is no automated end-to-end layer. The natural shape for one is Flutter's
`integration_test/` driven by `flutter drive`, against the Firebase Auth emulator and
`npm run dev:test` — two seeded caregivers, so the flows that need a second person
(validation, bounties, personal-time requests) can be exercised.

---

## Layer 1 — Backend Unit Tests

**Runner:** Node.js built-in test runner (`node --test`)
**Location:** `backend/tests/`
**Dependencies:** `supertest` (already installed), no DB required — all tests use mock DB clients
**Architecture:** Each service function receives a `client` parameter. Tests pass a mock client that returns pre-programmed query responses in order, so no real database is needed.

### `activityService.test.js` — 21 tests

Tests the business logic in `backend/src/services/activityService.js`.

#### `completeActivity`
| Test | What it verifies |
|---|---|
| awards coin_value to assignee | Coins equal to `coin_value` are credited when an activity is completed |
| awards coin_value + bounty_amount when bounty is set | Total award includes both base coins and any offered bounty |
| returns 404 when activity not found | Missing activity returns HTTP 404 error object |
| awards zero coins when coin_value is 0 | No coin queries are made if value is zero (query count assertion) |

#### `validateActivity`
| Test | What it verifies |
|---|---|
| awards coins to assignee when validated by another user | Caregiver validates a pending activity, coins go to assignee |
| returns 403 when user tries to validate their own activity | Self-validation is blocked |
| returns 409 when activity is not pending_validation | Wrong status returns conflict error |
| returns 404 when activity not found | Missing activity returns 404 |

#### `offerBounty`
| Test | What it verifies |
|---|---|
| deducts coins from offerer and sets bounty | Offerer's balance is reduced by the bounty amount |
| returns 403 when user is not the assignee | Only the task owner can offer a bounty |
| returns 409 when user has insufficient coins | Balance check blocks insufficient offers |
| returns 404 when activity not found | Missing activity returns 404 |

#### `acceptBounty`
| Test | What it verifies |
|---|---|
| reassigns activity to accepting user | `assigned_to` is updated to the accepting user |
| returns 409 when user already owns the shift | You cannot accept your own bounty |
| returns 409 when activity is completed | Completed activities cannot change assignee |
| returns 409 when no bounty is set | No bounty available returns conflict |

#### `revertActivity`
| Test | What it verifies |
|---|---|
| deducts coins and marks activity as rejected | Coins are taken back and status set to rejected |
| refunds bounty to original offerer on revert | Bounty amount is returned to the person who offered it |
| appends a reversal instead of rewriting the credit | No `UPDATE coin_ledger`; a negative `activity_reverted` row is inserted |
| a paid coverage shift cannot be reverted | Coverage only ends with its personal time |
| returns 403 when user is not the assignee | Only the task owner can revert |
| returns 409 when activity is not completed | Only completed activities can be reverted |

#### `listActivities`
| Test | What it verifies |
|---|---|
| returns 403 when user is not a family member | Non-members cannot list activities |

---

### `familyService.test.js` — 23 tests

Tests `backend/src/services/familyService.js` and `backend/src/services/memberService.js`.

#### `createFamily` — budget calculation
| Test | What it verifies |
|---|---|
| sets budget to 1000 when no objectsOfCare | Default fallback budget when no dependents |
| calculates 720 per full_time dependent | Each full-time dependent adds 720 coins/month |
| calculates 360 per part_time dependent | Part-time dependent adds 360 coins/month |
| sums budget across multiple dependents | Two dependents (full + part) = 1080 coins/month |

#### `deleteFamily`
| Test | What it verifies |
|---|---|
| deletes immediately when only one caregiver | Single-caregiver family is deleted instantly |
| creates deletion request when multiple caregivers | Multi-caregiver families require consensus |
| returns 409 when deletion request already pending | Duplicate requests are blocked |
| returns 404 when family not found | Non-existent family returns 404 |

#### `approveDeletion`
| Test | What it verifies |
|---|---|
| deletes family when all approvals received | Final approval triggers actual deletion |
| returns pendingApproval when other approvals still needed | Partial approval leaves family intact |
| returns 404 when request not found | Missing deletion request returns 404 |

#### `joinByToken` (invite link flow)
| Test | What it verifies |
|---|---|
| returns 410 when link is revoked | Revoked links are rejected |
| returns 410 when link is expired | Expired links are rejected |
| returns 410 when max uses reached | Used-up links are rejected |
| returns 409 when already an active member | Duplicate membership is blocked |
| returns 404 when token not found | Invalid token returns 404 |

#### `joinByInvitation` (email invite flow)
| Test | What it verifies |
|---|---|
| returns 400 when user has no email | Accounts without email cannot use email invitations |
| returns 403 when no pending invitation for email | Only invited emails can join |

#### `approveMember`
| Test | What it verifies |
|---|---|
| returns 404 when pending member not found | Approving a non-existent pending member returns 404 |
| returns success when member approved | Valid approval succeeds |

#### `removeActor`
| Test | What it verifies |
|---|---|
| returns 403 when actor is not a pet | Only pets can be removed (not children or elderly) |
| returns 404 when actor not found | Non-existent actor returns 404 |
| removes pet and adjusts budget | Removing a pet decreases the monthly coin budget |

---

## Layer 2 — Flutter Unit and Widget Tests

**Runner:** `flutter test` · **Location:** `fluterFront/test/`

| File | What it covers |
|---|---|
| `absence_dialog_test.dart` | Picked days become whole-day windows (≥ 24 h, DST-safe); the dialog explains the rule |
| `activity_kind_test.dart` | `isSelfActivity`: only `category = 'self'` is personal time; legacy and unknown rows are family work |
| `personal_time_test.dart` | Every personal-time type and repeat has a label; unknown types fall back; the create sheet's fields |
| `starter_packs_test.dart` | Questionnaire areas per dependent type, the `starterTasks` payload, localized area labels |
| `l10n_test.dart`, `locale_test.dart`, `arb_plurals_test.dart` | Every ARB file is complete, locales resolve, ICU plurals render |
| `error_localization_test.dart` | Backend errors map to localized messages |
| `avatar_upload_test.dart` | Content-type sniffing: JPEG/PNG/WebP accepted, HEIC and truncated input refused |
| `legal_links_test.dart` | Privacy/terms URLs are absolute https, match `nginx.conf`, labelled in every language |
| `session_rejected_test.dart` | 401/403 sign out; a flaky connection never does; a rejected session is not "no family" |
| `widget_test.dart` | UI kit smoke test, help sheet, coach marks, activation checklist |

`flutter analyze` must also be clean.

---

## How to run

```bash
cd backend && npm test                              # backend unit
cd fluterFront && flutter analyze && flutter test   # Flutter
```

Verifying a migration against a real database:

```bash
docker run --rm -d --name cc -e POSTGRES_PASSWORD=test -e POSTGRES_DB=cc -p 55432:5432 postgres:16
cd backend && DATABASE_URL="postgres://postgres:test@localhost:55432/cc" npm run db:init
```

Run `db:init` twice — it must stay re-runnable.
