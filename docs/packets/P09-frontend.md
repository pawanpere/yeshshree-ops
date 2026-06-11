# Frontend wave: Flutter app, all internal-pilot screens — WRITTEN (Cowork, 2026-06-12)
4 parallel agents (J auth/home/notifications, K gate/QC/store, L supervisor/planning,
M management) on an 8-file foundation. 32 Dart files, 24 screens. NOT YET COMPILED —
no Flutter SDK in the sandbox; first `flutter analyze` happens on the dev machine.

## Foundation (contracts)
theme.dart (app-map visual language: navy/blue/status colors) · strings.dart (S.t(en,mr)
at call sites — DEVIATION from ARB, mechanical consolidation later) · api_client.dart
(bearer + one-shot refresh + error envelope + clock-skew; HAND-WRITTEN clients vs
generated — DEVIATION, swap is mechanical against openapi.json) · auth_state.dart
(session in shared_preferences — move to flutter_secure_storage later) · retry_queue.dart
(client_ref posts queue offline, drain every 30s; safe by backend idempotency) ·
widgets/common.dart (KpiCard/AppCard/AlertBanner/TileButton/StatusBadge/ProgressBar) ·
router.dart (role redirects; THE class-name contract — verified, all 24 resolve).

## Screens
Auth: login (clock-skew aware), station PIN switch (device registration), vendor mock-OTP
(dev_code banner), force-update. Home: role+station tile grids, retry-queue sync banner.
Gate: pending scans (+scanner-offline banner), entry form (scan prefill, PO lock,
consignment 409 dialog, complete-backfill mode), unmatched folder, offline backfill.
QC: GR worklist+form (NO received-qty prefill per Domain_QA, full-lot warning, hard-anomaly
re-type/escalate dialog, weighbridge field). Store: issue (exposure bars, waiver banner),
dispatch (dynamic lines), billing (record SAP invoice, mismatch-reason dialog, confirm sale).
Supervisor: cockpit (line/shift pick + plan cards) → confirm sheet (HERO: reasons en+mr,
process loss, interim/close, queue-first offline) → history (sync badges + QUEUED rows +
corrections) → holds. Planning: home KPIs, schedule (create/diff/sanity/release/re-release),
config (6 tabs incl guarded ops_mode flip). Management: dashboards (4 tabs, 30s refresh,
INR formatting), approvals inbox (decide/override/delegations), anomaly register.

## Agent-reported follow-ups (honest list, none blocking first compile)
retry-queue drops 4xx on drain with no user surface (queued doc rejected later → invisible;
needs a 'failed sync' list) · scans/pending response lacks suggested_vendor_id + /master/vendors
lacks gstin filter (gate form shows GSTIN hint instead of preselecting) · no unread-count
endpoint (home bell has no badge) · reason labels in dashboards are en-only (backend sends
label_en only there) · delegations dialog needs raw user IDs (no user-search endpoint) ·
dispatch lines carry no value → billing line values start empty · ETag/304 not exploited
client-side · ProgressBar ramp is achievement-oriented (exposure bars rely on red labels).

## Handoff — Kartik, first compile (paste errors back, I fix)
    cd yeshshree-ops/app
    flutter create . --platforms=android,web   # generates android/ web/ around lib/
    flutter pub get
    flutter analyze                            # expect a handful of fixes — paste output
    flutter run -d chrome --dart-define=API_URL=http://localhost:8000
Login with seeded demo users (demo1234 / PIN 1234), backend running via docker-compose.
