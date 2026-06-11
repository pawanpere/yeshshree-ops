# SYSTEM MAP — load this first when debugging or changing anything

One system: FastAPI+Postgres backend (`backend/`), Flutter client (`app/`), Windows scan
watcher (`gate-agent/`). Plant 1117 captures gate→QC→stock→production→dispatch→billing on
phones; SAP stays source of truth via a transactional outbox → SFTP CSV. Parallel-run
pilot: the app must NEVER block the physical plant. Invariants: CLAUDE.md (binding).
Deep dives: `docs/planning/Yeshshree_Backend_Architecture.md` (§4 schema, §5 mechanisms,
§11 hardening) · `app/ARCHITECTURE.md` (frontend rules). This file is the index into them.

## 1. Where behavior lives (domain → files)

| Domain | Logic | Router | Models | Tests | Screen(s) |
|---|---|---|---|---|---|
| Auth/JWT/PIN/OTP | services/auth.py, core/security.py, core/deps.py | api/auth.py | identity.py | test_auth.py | features/auth/* |
| Audit | core/audit.py (middleware + record()) | — | system.py:AuditLog | test_audit.py | — |
| Master/config CRUD | services/master.py (apply_update whitelist) | api/master.py, api/config.py | master.py, config_tables.py | test_master_config.py | planning/config_screen |
| Schedules/plans | services/plans.py (+importers/schedule_csv.py PROVISIONAL) | api/plans.py | planning.py | test_plans.py | planning/schedule_screen |
| Gate entries | services/gate.py | api/gate.py | gate.py | test_gate.py | gate/* |
| Scan decode | services/scan_decode.py (zxing/pypdfium2) | api/scans.py (also heartbeat) | gate.py:GateScan, system.py:StationStatus | test_scans.py (golden: 3 real PDFs in data/) | gate/scans_pending |
| Goods receipt | services/receiving.py | api/receiving.py | inventory.py | test_receiving.py | qc/gr_form |
| Anomaly engine | services/anomaly.py (interface) + anomaly_rules.py (rules) | api/receiving.py (/anomalies) | workflow.py:Anomaly | test_receiving, test_closeout | management/anomalies |
| Stock/issues | services/inventory.py, services/issuing.py | api/inventory.py | inventory.py | test_inventory, test_issuing | store/issue |
| Approvals/override/delegation | services/approvals.py + approval_handlers.py (registry) | api/approvals.py | workflow.py | test_approvals.py | management/approvals |
| Escalations | services/escalations.py (predicates+scan+resolve) | — (worker job) | workflow.py | test_escalations, test_closeout | — |
| Notifications | services/notifications.py, services/sweeps.py | api/notifications.py | workflow.py | test_escalations, test_closeout | notifications/* |
| Production confirm | services/production.py | api/production.py | production.py | test_production.py | supervisor/* |
| Dispatch/billing | services/outbound.py | api/outbound.py | outbound.py | test_outbound.py | store/dispatch, billing |
| Dashboards | services/dashboards.py (read-only) | api/dashboards.py (ETag) | (joins) | test_dashboards.py | management/dashboards |
| SAP outbox/SFTP | sap_sync/batcher.py + services/tx.py (enqueue) | api/exports.py (reconciliation) | system.py | test_worker_outbox, test_outbox | — |
| Worker jobs | app/worker.py JOBS list | — | — | run jobs directly w/ fake now | — |
| Seed/SAP imports | importers/seed.py, sap_files.py, sap_stock.py | api/inventory.py (/imports/sap-stock) | — | test_importers.py (golden: 5 real exports) | — |
| Numbering / files / idempotency | services/numbering.py · files.py · tx.py | — | config_tables:DocSequence, gate:File | test_outbox, test_closeout | — |

Frontend cross-cuts: core/api_client.dart (errors/refresh) · core/retry_queue.dart
(offline posts) · core/router.dart (route↔class contract) · widgets/common.dart.

## 2. Extension registries (add behavior WITHOUT touching the engine)

| To add… | Do this | Engine that picks it up |
|---|---|---|
| anomaly rule | `@rule('context')` fn in services/anomaly_rules.py + threshold in app_settings | anomaly.run_rules() at write paths |
| approval type | value into approvals CHECK + `@on_approve/@on_reject` in the owning service | approvals.decide()/override() |
| escalation timer | predicate in escalations.PREDICATES + EscalationRule config row | worker escalation_scan (5 min) |
| worker job | function(db) + tuple in worker.JOBS | worker loop / run_once() |
| outbox record type | value in tx.OUTBOX_RECORD_TYPES + enqueue_outbox call in the same txn | batcher.process_outbox |
| doc number prefix | doc_sequences row via numbering.next_doc_no(db,'XX') | — |
| status color (UI) | case in theme.statusColors | every StatusBadge |
| screen | file in features/<domain>/ + route in core/router.dart | go_router |

## 3. Tracing any transaction (the debug spine)

Every request: `X-Request-Id` response header == audit_log.request_id.
```sql
SELECT * FROM audit_log WHERE request_id='…';                   -- who/what/status
SELECT * FROM audit_log WHERE entity='goods_receipts' AND entity_id=42;  -- field diffs
SELECT * FROM stock_ledger WHERE ref_type='goods_receipts' AND ref_id=42; -- stock effect
SELECT * FROM sap_outbox WHERE record_type='GR' AND record_id=42; -- SAP postback state
SELECT * FROM sap_export_batches WHERE id=<batch_id>;            -- which file carried it
```
Idempotency: client retries carry the SAME client_ref → SELECT by client_ref finds the
one row. Stock balance = SUM(stock_ledger.qty) filtered — never a column.

## 4. Symptom → cause → files (cookbook)

| Symptom | First suspects |
|---|---|
| 422 ANOMALY_HARD on GR | rules in anomaly_rules.py; thresholds app_settings['anomaly_thresholds']; tolerance row missing in material_group_tolerances (services/receiving.py order: tolerance BEFORE rules) |
| GR refuses: GR_ENTRY_NOT_READY / GR_BACKFILL_PENDING | gate entry match_status/status/backfill_status — fix via link-po / complete-backfill (services/gate.py) |
| Issue stuck `waiver_pending` | approvals row pending → inbox roles/delegations (services/approvals.py); SLA reminders fire via escalation_scan; management can override (creates override_review) |
| Stock blocked unexpectedly | app_settings['ops_mode'] — parallel_run NEVER hard-blocks (inventory.check_stock); if blocking, mode=authoritative |
| Confirmation 422 CONFIRMATION_EXCEEDS_PLAN | pinned revision on shift_contexts.plan_revision vs LinePlan rows; plan_exceed_pct in settings (services/production.py) |
| Confirmation 409 NEEDS_ORDER | no production_orders row for (line,material) → hold queue; PPC resolves (holds_screen) |
| outbox rows `failed` | sap_outbox.last_error; attempts≥5; SFTP creds in env; retry = UPDATE status='pending'; crash recovery = batcher.recover_stuck (worker start) |
| dashboard number disputed | services/dashboards.py query + §3 trace SQL on the source rows; date attribution = shift_contexts.shift_date |
| 'Queued — will sync' forever | API_URL dart-define; backend up?; retry_queue.drain() drops 4xx SILENTLY (known gap — check server for the rejection in audit/anomalies) |
| login fails, password right | 401 details.server_time → device clock skew (api_client.isClockSkew); or session revoked by refresh-reuse detection (test_auth) |
| scanner 'offline' banner | station_status.last_heartbeat_at stale >5min; gate-agent log on the gate PC; heartbeat resolves the escalation |
| schedule release 422 | SPLIT_MISSING → config splits effective_from; RELEASE_WARNINGS → resubmit confirm_warnings:true (services/plans.py sanity_checks) |
| seed/golden test breaks after new SAP file | header-driven parsers in importers/sap_files.py — SAP changed columns; fix mapping, never the golden files |
| duplicate invoice at gate | 409 DUPLICATE_INVOICE is intentional → consignment continuation (services/gate.py §11.6) |

## 5. Status state machines (legal transitions only)

- gate_entries.status: open → gr_done | cancelled; match_status: unmatched ↔ matched → (consumable)
- goods_receipts: posted | cancelled (corrections = new rows, never edits)
- issues: posted | blocked | waiver_pending → posted/cancelled | corrected
- approvals: pending → approved | declined | hold | overridden (override ⇒ +override_review row)
- sap_outbox: pending → batched → sent → acked; failures → pending(attempts++) → failed(≥5)
- sap_export_batches: building → uploaded → acked | failed (building after crash ⇒ recover_stuck releases rows)
- confirmations: posted → corrected; holds: open → resolved | discarded
- schedules: draft → released → superseded (rollback = re-release as NEW version; nothing deleted)
- anomalies: open → in_review → resolved · notifications: read_at / acted_at (acted stops blocker repeats)

## 6. Running things

Sandbox (no docker/flutter): `python3 -m pytest -q -m "not postgres"` from backend/ — run
in 3–4 file-chunks if a 45s cap applies. Dev machine: `make verify` (full), `make seed`,
worker: `python -m app.worker` (or run_once(['outbox'])). Flutter: app/ARCHITECTURE.md
handoff. Golden files in data/ are read-only truth (5 SAP exports + 3 scanned invoices).
The e2e spec: backend/tests/test_e2e_thin_slice.py — read it to see the whole system
exercised in order; if your change breaks it, your change is wrong (or the spec moved
and BOTH must change in one commit).

## 7. Things that look like bugs but are decisions

No DELETE routes anywhere (deactivate instead) · POST returns 200 not 201 (idempotent
replay = identical response) · received_qty never prefilled at QC (100% count, Domain_QA)
· stock can go negative in parallel_run (warn-only, ADR-003) · full-lot reject writes ZERO
stock rows · mat_type has no CHECK (SAP owns that vocabulary) · 5× multiplier only on
shortage debits, full-lot = 1× · plan revised mid-shift doesn't block (pinning §11.10) ·
hsn_check='n/a' (no honest HSN↔mat_group mapping yet) · provisional schedule CSV (ADR-005).
