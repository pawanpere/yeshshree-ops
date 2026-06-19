# Roles pilot: login → role → role-scoped app — IN PROGRESS (2026-06-20)

Turns the ui2 Flutter app (39 screens, one big phone gallery) into a **role-scoped
pilot**: login → pick a role → see ONLY that role's screens, structured so a role can
later be locked to the account. 8 roles. Built on `main` (branch `feat/roles-pilot`),
backend rebuilt fresh (Codex's local-only vendor/admin branch is NOT used).

Ground rules (from the build prompt): ui2 design system, bilingual `S.t('en','mr')`,
all backend through `ui2/data/api2.dart`, error envelope `detail:{code,message_en,
message_mr,details}`, vendor scoping in the SERVICE layer from JWT `vendor_id`, never
weaken tests / break the old `features/` app / invent infra; backend changes get a
migration (if schema) + tests. Verify each phase, commit, check in before the next.

## Scope decisions (locked with the user)
- **8 roles**: gate, quality, production, store, planning (PPC), management, admin, vendor.
- Material **shortage** screen/backend — OUT of scope.
- Planning lives in **SAP**: do NOT build scheduling / split / schedule upload / cascade.
  Planning role only VIEWS the plan + resolves holds.
- Users & devices setup — IN scope (backend included, Phase 5).
- Vendor orders/financials — IN scope (new vendor-scoped endpoints, Phase 6).
- Job-work reconciliation — DEFERRED.
- `saleForm` scrap-vs-FG split — **SKIP** (leave the screen as-is; do not fix its
  hardcoded dispatch_id in Phase 1).
- Phase 4 component stock → **new component category via migration**.

## Phases
- **Phase 0 — role shells. ✅ DONE (commit b76a748).** Login, entitlement-gated role
  picker, role-scoped phone shell + responsive office shell, role→screens map,
  ComingSoon placeholder for the 14 not-yet-built role screens. Shell owns nav; screens
  are content-only. `?role=<name>` is an offline demo deep-link (local devSignIn, no
  backend). Verify: analyze clean, flutter test 8/8, web build OK. Frontend only.
- **Phase 1 prep — dev CORS. ✅ DONE.** Backend had no CORS, so the Flutter WEB build
  couldn't reach the API cross-origin (silent demo fallback; Android is unaffected —
  native HTTP). Added `CORSMiddleware` (explicit `CORS_ORIGINS` + any `localhost:<port>`
  via `CORS_ALLOW_LOCALHOST`, default on for dev). +3 tests (`test_cors.py`).
- **Phase 1 — wiring + typed fields + layout. IN PROGRESS.**
  - **1a wiring. ✅ DONE.** The cockpit and confirmation-history screens were 100%
    hardcoded mockups (no backend call at all); both are now data-driven. Cockpit ←
    `/plans/supervisor-view?line_id=&date=today` (aggregates planned/good/reject →
    shift-plan card, yield, rejects tile) + `/approvals/inbox` (the waiting-approval
    banner). Conf history ← `/confirmations?date=today` (enriched with material names).
    Gate arrivals ← `/gate-entries?status=open` (was the invalid `status=pending`),
    live rows normalised to the screen's shape. Notifications approval card now uses
    the REAL approval id from `/approvals/inbox` (was hardcoded `/approvals/1/decide`).
    saleForm left untouched (skip, per decision). All reads keep the DEMO fallback.
    Verified: all four endpoints 200 through CORS; analyze clean; tests 8/8.
  - **1b every qty field typed-editable. NEXT.**
  - **1c remaining overflow fixes + extend the stress test (fail on infinite-height).**
- **Phase 2** — remove in-app camera scan; gate inbox fed by the scanner-watcher.
- **Phase 3** — quality worklist (`/gate-entries?status=open&match_status=matched`).
- **Phase 4** — inbound RM vs components (new component category, migration); GR routes
  by type; job-work-return inward category.
- **Phase 5** — users & devices (backend + admin office UI).
- **Phase 6** — remaining role screens (management dashboards/approvals/anomalies;
  planning plan-view + holds; store stock-browse; admin master + settings; vendor
  orders/financials via new vendor-scoped endpoints).

## Honest follow-ups / known issues
- **`?role=` web previews show DEMO data, not live** — until CORS is deployed in front
  of a running backend, OR the web build is served same-origin behind a reverse proxy.
  On a real Android/tablet build this never applies.
- **2 pre-existing backend test failures (predated this branch, from `P11-final`) —
  now FIXED in Phase 1 (user approved):**
  1. `test_every_architecture_table_exists` — added `model_part_factors` (a real
     `config_tables` model) to the test's `EXPECTED_TABLES`.
  2. `test_thin_slice` — `confirmed_good` returned `0` after a confirmation. **Root
     cause: timezone.** `_now()` is UTC, so the confirmation's `shift_date =
     now.date()` was the UTC day; between 00:00–05:30 IST that is the *previous* day,
     so it never matched `line_plans.plan_date` / the date the cockpit queries → the
     live `confirmed_totals` join missed. Fix: a plant-local `_business_date()` (new
     `PLANT_TZ=Asia/Kolkata` setting) for the `shift_date` default. Deterministic
     regression test added (`test_shift_date_tz.py`). `_now()` itself stays UTC.
- **Deferred (noticed while fixing the above, NOT touched):** the shift *auto-close*
  job (`_shift_end` / `shift_auto_close_job`) combines the local shift window time with
  `now.tzinfo` (UTC), so an IST shift boundary is compared in the wrong zone (~5.5h
  off). Same timezone class of bug; out of the pilot's scope — flagged for Kartik.

## Verify (sandbox-safe; full `make verify` runs on Kartik's machine)
    cd app && ~/flutter-sdk/bin/flutter analyze lib test && ~/flutter-sdk/bin/flutter test
    cd app && ~/flutter-sdk/bin/flutter build web --dart-define=UI2_MODE=true
    cd backend && .venv/bin/python -m pytest -m "not postgres" -q
Offline role preview (no backend): build web, serve `app/build/web`, open
`http://localhost:<port>/?role=<gate|quality|production|store|planning|management|admin|vendor|picker>`.
