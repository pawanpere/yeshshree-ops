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
- **Phase 1 — wiring + typed fields + layout. NEXT.** 1a fix wrong calls (cockpit →
  `/plans/supervisor-view` line_id+date; gate arrivals → unmatched/`?status=open` not
  `pending`; conf history `date=today`; approvals real id; saleForm SKIP). 1b every qty
  field typed-editable. 1c remaining overflow fixes + extend the stress test.
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
- **2 pre-existing backend test failures (NOT from this branch — predate it on `main`,
  from the `P11-final` commit):**
  1. `test_models.py::test_every_architecture_table_exists` — the `model_part_factors`
     table exists in the models but isn't in the test's `EXPECTED_TABLES` (stale list).
     Trivial reconciliation (update the set + Architecture §4 schema).
  2. `test_e2e_thin_slice.py::test_thin_slice` — `plans/line-plans.confirmed_good`
     returns `0` instead of `215` after a confirmation. Root area: `confirmed_totals()`
     (production svc) joins confirmations to a date via `ShiftContext.shift_date`; the
     live join into the plan view (`_plan_rows`) comes back empty. **This is the exact
     field the production cockpit reads — fix before/with the Phase 1 cockpit wiring.**

## Verify (sandbox-safe; full `make verify` runs on Kartik's machine)
    cd app && ~/flutter-sdk/bin/flutter analyze lib test && ~/flutter-sdk/bin/flutter test
    cd app && ~/flutter-sdk/bin/flutter build web --dart-define=UI2_MODE=true
    cd backend && .venv/bin/python -m pytest -m "not postgres" -q
Offline role preview (no backend): build web, serve `app/build/web`, open
`http://localhost:<port>/?role=<gate|quality|production|store|planning|management|admin|vendor|picker>`.
