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
  - **1b every qty field typed-editable. ✅ DONE.** New shared `QtyField2` widget (a
    numeric, keyboard-editable field that keeps the +/- steppers working) replaces the
    read-only stepper counts in confirm (good/reject/downtime), issue, and over-limit
    issue. gate-QC and GRN already used numeric TextFields; gate-match only displays the
    PO qty; saleForm skipped. 5 widget tests (`ui2_qty_field_test.dart`).
  - **1c layout + stress test. ✅ DONE.** The render stress test now also fails on
    UNBOUNDED/INFINITE-HEIGHT layout errors (a flex child or scroll view given
    unbounded vertical space), not just RenderFlex overflow. Sweeping all 39 screens
    in en+mr surfaced exactly the two the report flagged — `gateScanned` (deleted in
    Phase 2) and `saleForm` (out of scope) — both allow-listed with a shrink-this-list
    TODO; the other 37 are clean. The report's RenderFlex overflows were already fixed
    in the earlier layout-hardening pass. Tests: 13/13; web build OK.
- **Phase 2 — remove in-app camera scan. ✅ DONE.** Deleted the two in-app camera
  screens (`gateScan` viewfinder + `gateScanned` read-back) and their ids / registry
  entries. The app no longer captures with the phone camera — the gate inbox
  (`gate_arrivals` ← `/gate-entries?status=open`) is fed by the ScanJet scanner-watcher
  (which posts entries to the backend). Tapping a matched arrival now opens the
  match-order flow (`gateMatch` → send to quality); the footer notes scans arrive
  automatically and offers a manual "Add a gate entry" (`offlineGate`). Removed the now
  non-existent `gateScanned` from the stress-test allow-list, so the test got stricter
  for free. Verified: analyze clean, tests 13/13, web build OK; adversarial multi-lens
  review (reachability / UX-flow / bilingual / spec) found + fixed 3 issues: the manual
  "Add a gate entry" path (`offlineGate`) was framed offline-only ("queued / when back
  online") though it's now used online too — reworded to neutral copy and made the saved
  screen **outcome-aware** (posted-live vs queued-offline via `res.queued`); renumbered
  the gate step counter (was 1/6→4/6 after deleting steps 2–3) to a contiguous 1–4/4;
  refreshed the stale `gate_arrivals` "(tap to scan)" docstring.
- **Phase 3 — quality worklist. ✅ DONE.** New `quality_worklist_screen` (replaces the
  ComingSoon placeholder, registered + in `kScreens`): the quality role's inward-QC queue,
  fed by `GET /gate-entries?status=open&match_status=matched` via `Data.qualityWorklist()`
  (normalised + material-name enriched, null-safe for sparse live rows, DEMO fallback).
  Tapping a card carries the entry into the QC→GRN flow: a LIVE entry's real `gate.entryId`
  is set so `gate_grn` receipts THAT entry (it now prefers a carried id and only
  self-creates otherwise); a demo row / the gate-match path clears it so the GRN
  self-creates. `gate_qc` gained an entry-context subtitle. Adversarial 4-lens review
  found + fixed 3 issues from the new context-carry: (HIGH) a stale `gate.entryId` could
  let the Quality role double-receipt an already-received entry (the role's tabs are
  independent roots and the global `Ui2Flow` bag persisted) → `PhoneShell.tab()` now
  clears ephemeral flow on any tab switch, and `gate_grn` clears the entry id after a
  successful receipt (regression test added); (HIGH) the GRN summary was hardcoded
  ("CR coil 2.5mm" / fake PO) and ignored the picked entry → now shows the carried
  material + supplier and an honest PO; (MED) the QC subtitle was stale on a cold tab
  open → fixed by the same tab-clear. Verified: live endpoint returns 1 matched row
  through CORS, analyze clean, tests 14/14, web build OK.
- **Phase 4 — inbound RM vs components. ✅ DONE.** New plant stock `category`
  (`rm`/`component`/`fg`) on materials (model CHECK + a hand-authored Alembic migration
  `0001_material_category_and_inward.py` — the repo has no Alembic baseline yet, schema
  is built via `create_all`, so the migration is the reviewable DIFF to reconcile on the
  dev machine). `Material.stock_location` routes inbound GR stock: components → the new
  `COMP` store, raw material → `RM` (existing materials default `rm` → unchanged). Added
  `job_work_return` to the gate `inward_category` (DB CHECK + the `InwardCategory` schema
  Literal). Frontend: the quality worklist carries the material category and the inward-QC
  + GRN screens **branch by type** — components are counted in pieces, raw material is
  weighed on the weighbridge (kg). 7 backend tests (`test_components.py`: stock_location,
  CHECKs, schema literal, component GR→COMP, rm GR→RM). **Scope boundary (documented):**
  only the INBOUND (GR) path routes by category; component *consumption* + stock-balance
  routing is a deferred follow-up (existing rm flows are byte-for-byte unchanged).
  Verified: backend 145/145, flutter analyze clean, tests 14/14, web build OK.
- **Phase 5 — users & devices. ✅ DONE.** New admin-only backend (`api/identity.py`,
  `services/identity.py`, `schemas/identity.py`): `/master/users` + `/master/station-devices`
  list/create/update. Passwords + PINs are hashed (never read back; `has_pin` flag only),
  username/device_key immutable, no deletes (deactivate via is_active), unique-conflict →
  409, every change audited; `require("admin")` gates all routes. 7 tests (`test_users.py`)
  incl. role-guard, hashing+login, dup→409, invalid-role→422, audited password change,
  deactivate-hides. Frontend: `admin_users` + `admin_devices` office screens (list + add
  form with role/station chips + deactivate), via `Data.users/stationDevices/mutate/patch`,
  demo fallback, bilingual. Verified: backend 153/153, analyze clean, tests 14/14.
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
