# Mobile UX Phase 6 — Implementation Brief

> **For a coding agent working without prior context.** Phase 6 follows the sixth design
> critique of 2026-10-11 (`.impeccable/critique/2026-10-11T07-58-00Z__fluterfront-lib-screens.md`,
> 34/40, no P0/P1). Phases 3–5 made every screen calm and every total say what it counts.
> Phase 6 is about recovery: undo for removing a task, errors that stay long enough to act
> on and can be retried, and server errors in the user's language. It also folds Stats ›
> Members into one card. Same ground rules: one commit per ticket on `mobile-ux-phase6`, no
> whole-file `dart format`, every new string in all four ARB files, tokens from
> `lib/theme/app_theme.dart`, Material 3 components, `flutter analyze` and `flutter test`
> clean, `cd backend && npm test` clean. **Backend changes** (P6-4, P6-5) reach production
> only with the next deploy; the app must keep working against today's backend.

> **Status (2026-10-12):** done on `mobile-ux-phase6` (not merged). P6-4 and P6-5 need a
> backend deploy; until then the app falls back to the server's English text, as before.

## Decisions (2026-10-12)

1. **Members is one card.** The family figures are four sentences in one "This family"
   card; one "By caregiver" chip opens every per-person comparison. Per-person "Tasks
   done" shows a count, not "x of N" (visible and fair, not competitive).
2. **Removing a task is undoable.** The removal waits for the Undo snackbar to close
   before it reaches the server (deferred delete). Series removal and personal time keep
   their confirmation dialogs.
3. **Server errors carry a stable code.** The backend adds `code` (and `params` where the
   text names something) next to the English `error`; the app maps codes to ARB keys and
   falls back to the English text for unknown codes. Admin routes are out of scope.
4. Target: about 37/40 (heuristics 3, 8, 9 from 3 to 4).

## P6-1 · Members: one card (critique P2 #3, P3 #4, minor)

One "This family" card: balances right now, due tasks done (and waiting), bounties
(offered, earned, returned, still open), most claimed reward. One chip opens the
per-person breakdowns; "Tasks done" per person is a count. The single-bar "Most popular
rewards" chart goes.

## P6-2 · Undo for removing a task (critique P2 #2)

Removing a single care or household task hides it at once and shows "Removed · Undo";
the DELETE is sent when the snackbar closes without Undo. A failed Undo or a failed
deferred delete shows an error instead of being swallowed.

## P6-3 · Errors you can act on (critique P2 #2, Phase 5 lead review #3, #4)

Error toasts stay 10 s with a close icon; an error from `runAction` offers "Try again".
5xx failures read "Something went wrong on our side. Try again in a moment." in the
user's language instead of the backend's English "Failed to …" text or "Request failed
(500)".

## P6-4 · Error codes in services (backend, critique P2 #1)

A helper turns a service error `{ code, message, key, params }` into
`{ error, code, params }`; every user-facing service error gains a `key`.

## P6-5 · Error codes in routes and middleware (backend)

Route-level 4xx literals and middleware errors gain a `code`; 5xx answers carry
`code: 'internal'`. `docs/error-codes.md` lists every code with its English text and
params. A test fails on any non-admin error answer without a code.

## P6-6 · The app speaks the codes (critique P2 #1)

`ApiException` keeps `code` and `params`; `AppState._localizeError` maps each code to an
ARB key in all four languages; unknown codes fall back to the server's English text.

## P6-7 · Small leftovers (critique P3 #6, minor)

Catalogue task names wrap to two lines instead of truncating; value labels in "Time given
and taken" use ink colours with enough contrast.

## As built

| Ticket | Commit | Notes |
|---|---|---|
| P6-1 | `3823bf0` | Section labels 16 px, person names 13 px grey, so the per-person view has two levels. |
| P6-2 | `8d2ea71` | In this Flutter SDK a SnackBar with an action never times out (`persist` defaults to true), so every Undo SnackBar sets `persist: false`; the schedule and move Undo snackbars had never closed by themselves. |
| P6-3 | `9d72c9c` | Retry only for timeouts, network errors, 5xx, 408 and 429. `ToastListener` is now public (`@visibleForTesting`). |
| P6-4 | `93fcebf` | 81 service keys; `personalTimeSeriesBlocked` carries `reasonCode` / `reasonParams` so both halves translate. |
| P6-5 | `73eea02` | 124 codes in `docs/error-codes.md`; unknown paths answer `notFound` as JSON. |
| P6-6 | `830fed7` | `adminOnly` falls back to English. es/fr error texts use the app's "tiempo personal" / "temps personnel". |
| P6-7 | `c5bc3d5` | The repeat icon is an inline span on the title's last line. |

Flutter: 315 tests, analyze clean. Backend: 233 tests.
