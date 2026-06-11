# Yeshshree Operations App — Backend Architecture (v2)

Companion to `Yeshshree_MVP_Backend_Plan.md` (the *what*); this document is the *how*. Date: 10 Jun 2026.
v2 changes: §11 added — every gap from `Yeshshree_Failure_Scenarios.md` §9 turned into concrete schema/endpoints/jobs. Build execution is decomposed into agent work-packets in `Yeshshree_AI_Build_Playbook.md`.

---

## 1. Principles

**Modular monolith.** One FastAPI service, internally split by domain. Modules talk through Python function calls, never HTTP. If a module ever needs independent scaling (none will at this load), it can be extracted — but we don't pay that cost up front.

**Facts are append-only.** Stock movements, confirmations, audit entries, and outbox rows are never updated in place. Corrections are new rows referencing the original. This is what makes the system trustworthy in a parallel-run pilot and trivially debuggable: history is always reconstructible with SQL.

**Config over code, code over config-language.** Business *parameters* (thresholds, splits, reason codes) live in DB tables editable from the admin screen. Business *logic* (what a limit check does) lives in plain Python — never in SQL triggers, stored procedures, or a rules DSL. One place to look.

**Boring and explicit.** No metaprogramming, no clever abstractions. Every endpoint is readable top-to-bottom: validate → check rules → write rows → write audit + outbox → respond.

---

## 2. System topology

```
┌─ Plant ───────────────────────────────┐
│ Gate PC: ScanJet + gate-agent (.exe) ──── HTTPS push ──┐
│ Station devices / personal phones      │               │
│   Flutter Android app ─────────────────── HTTPS ───────┤
└───────────────────────────────────────┘               │
  Office/anywhere: Flutter Web (managers, planning) ─────┤
  Vendors: Flutter Android (BYOD) ───────────────────────┤
                                                         ▼
                                            ┌─ Railway/Render ────────────┐
                                            │  api (FastAPI, 1 container) │
                                            │  worker (same image,        │
                                            │    `python -m app.worker`)  │
                                            │  PostgreSQL 16              │
                                            └──────┬──────────┬───────────┘
                                                   │          │
                                       Cloudflare R2      SAP SFTP server
                                       (scans, photos)    (inbound exports /
                                                           outbound postback)
```

Two containers from one Docker image: `api` serves HTTP; `worker` runs scheduled jobs (APScheduler): outbox batcher + SFTP upload (5 min), SFTP inbound poll (15 min), anomaly baseline recompute (nightly), notification fan-out. No Celery/Redis — jobs are idempotent and DB-coordinated (`FOR UPDATE SKIP LOCKED`).

Nothing inbound reaches the plant: the gate-agent and apps push outbound HTTPS only. No VPN, no port-forwarding.

---

## 3. Backend internal layering

```
backend/app/
├── api/            # one router per domain — HTTP concerns only (parse, call service, shape response)
├── services/       # ALL business logic — pure-ish functions taking a db session
│   ├── plans.py        # schedule release → line_plans + vendor_calloffs
│   ├── gate.py         # scan decode, PO match, gate entry
│   ├── receiving.py    # GR, shortage → debit draft
│   ├── inventory.py    # stock ledger writes, balance queries, days-of-cover
│   ├── issuing.py      # limit checks, waiver routing
│   ├── production.py   # confirmations, corrections
│   ├── outbound.py     # dispatch, invoice confirm
│   ├── approvals.py    # generic engine + per-type apply handlers
│   ├── anomaly.py      # rule registry
│   ├── numbering.py    # doc number sequences
│   └── dashboards.py   # aggregate queries
├── models/         # SQLAlchemy models, one file per domain
├── schemas/        # Pydantic request/response (source of the OpenAPI spec)
├── importers/      # SAP UTF-16 TSV parsers + schedule parser + seed
├── sap_sync/       # outbox batcher, SFTP client, ack processor, reconciliation
├── core/           # settings, db session, security, audit middleware, request-id
└── worker.py       # APScheduler entrypoint
```

Dependency rule: `api → services → models`. Services never import from `api`. Routers contain zero business logic — this keeps every rule unit-testable without HTTP and gives AI agents exactly one place to look for any behaviour.

---

## 4. Database schema

Conventions: BIGINT identity PKs; `client_ref UUID UNIQUE` on every user-created transaction (idempotency, §5.2); status/enum fields are TEXT + CHECK constraint (no Postgres enums — painless migrations); money NUMERIC(14,2), quantities NUMERIC(14,3); all timestamps `timestamptz`; `plant TEXT DEFAULT '1117'` on transactional tables (cheap multi-plant insurance). Soft delete = `is_active`, never row deletion on master data.

### 4.1 Identity & access

| Table | Columns |
|---|---|
| `users` | id, username UQ, password_hash, pin_hash NULL, full_name, role CHECK(admin·management·planning·plant_ops·supervisor·vendor), station NULL CHECK(gate·qc·store·ppc), vendor_id FK NULL, phone, language CHECK(en·mr), is_active, created_at |
| `station_devices` | id, device_key UQ, station, label, registered_by FK, last_seen_at, is_active |
| `auth_sessions` | id, user_id FK, refresh_token_hash, device_key NULL, expires_at, revoked_at NULL, created_at |
| `otp_codes` | id, phone, code, purpose, expires_at, used_at NULL — mock OTP now, real SMS later, same table |

### 4.2 Master data (seeded from the SAP exports; refreshed by SFTP imports later)

| Table | Columns |
|---|---|
| `vendors` | id, sap_code UQ, name, gstin, phone, city, state, credit_limit, qty_limit_mt, is_active |
| `materials` | id, sap_code UQ, description, mat_type CHECK(ROH·HALB·FERT), mat_group, uom, price, abc, is_active |
| `boms` | id, parent_material_id FK, alt_bom, is_active · `bom_lines`: id, bom_id FK, component_material_id FK, item_no, qty_per, uom, is_scrap_credit (negative BOM lines in the real export) |
| `purchase_orders` | id, sap_po_no, item_no, vendor_id FK, material_id FK, ordered_qty, open_qty, rate, uom, due_date, status, UQ(sap_po_no, item_no) |
| `lines` | id, name, plant, is_active · `line_materials`: line_id FK, material_id FK |
| `production_orders` | id, sap_order_no UQ, line_id FK, material_id FK, status |
| `customers` | id, sap_code, name, gstin — Bajaj now; table not hardcode |

### 4.3 Config (admin-editable, every change audit-logged)

| Table | Columns |
|---|---|
| `model_family_splits` | id, family, yesh_pct, laxmi_pct, effective_from |
| `reason_codes` | id, kind CHECK(reject·downtime), code UQ, label_en, label_mr, sort, is_active |
| `mills` | id, name, lead_days, moq_mt, sourcing — config screen now; mill-flag logic post-MVP |
| `plan_calendar` | cal_date PK, is_working, shifts JSONB |
| `app_settings` | key PK, value JSONB, description, updated_by, updated_at — anomaly thresholds, debit multiplier, GR target minutes |
| `doc_sequences` | doc_type, fiscal_year, next_no, PK(doc_type, fiscal_year) — G/GR/ISS/DN numbers, allocated under `SELECT … FOR UPDATE` |

### 4.4 Planning

| Table | Columns |
|---|---|
| `schedules` | id, customer_id FK, period, version, status CHECK(draft·released·superseded), source_file_id FK NULL, diff JSONB, created_by, released_by NULL, released_at NULL, UQ(customer_id, period, version) |
| `schedule_lines` | id, schedule_id FK, model_family, material_id FK NULL, bucket_date, qty |
| `line_plans` | id, plan_date, line_id FK, material_id FK, planned_qty, schedule_id FK, revision, status CHECK(active·superseded) — regenerated on each release; old revision kept |
| `vendor_calloffs` | id, vendor_id FK, material_id FK, calloff_date, qty, schedule_id FK, status |

### 4.5 Files & gate

| Table | Columns |
|---|---|
| `files` | id, storage_key, kind CHECK(scan·photo·import·export), mime, size_bytes, sha256, uploaded_by NULL (agent uploads use a service account), created_at |
| `gate_scans` | id, file_id FK, source CHECK(agent·phone), decode_status CHECK(decoded·partial·none), qr_payload JSONB NULL, pdf417_payload TEXT NULL, hsn_check CHECK(ok·mismatch·n/a), status CHECK(pending·linked·discarded), gate_entry_id FK NULL, created_at |
| `gate_entries` | id, doc_no (G-…), plant, vendor_id FK NULL, invoice_no, invoice_date, invoice_value NULL, irn NULL, po_id FK NULL, material_id FK NULL, qty_expected NULL, vehicle_no, driver_name, vehicle_photo_id FK NULL, invoice_photo_id FK NULL, match_status CHECK(matched·unmatched·consumable), status CHECK(open·gr_done·cancelled), client_ref UQ, created_by, created_at |

### 4.6 Inward, stock, issue

| Table | Columns |
|---|---|
| `goods_receipts` | id, doc_no (GR-…), gate_entry_id FK, po_id FK NULL, material_id FK, expected_qty, received_qty, accepted_qty, rejected_qty, qc_result CHECK(pass·fail), qc_remarks, shortage_qty, status CHECK(posted·cancelled), client_ref UQ, posted_by, posted_at |
| `debit_notes` | id, doc_no, goods_receipt_id FK, vendor_id FK, kind CHECK(shortage_5x), base_amount, multiplier, amount, status CHECK(draft·approved·declined·raised), approval_id FK NULL |
| `stock_ledger` | id, plant, material_id FK, location CHECK(RM·WIP·FG·AT_VENDOR), movement CHECK(GR_IN·ISSUE_OUT·PROD_IN·PROD_CONSUME·DISPATCH_OUT·ADJUST), qty (signed), uom, vendor_id FK NULL, ref_type, ref_id, created_by, created_at — **append-only; the only way stock changes** |
| `stock_balances` | VIEW: SUM(qty) by plant, material, location (+ vendor for AT_VENDOR). Materialize only if ever slow |
| `issues` | id, doc_no (ISS-…), destination CHECK(inhouse·vendor_sale·job_work), line_id FK NULL, vendor_id FK NULL, material_id FK, qty, uom, value, limit_check JSONB (snapshot of the check at decision time), status CHECK(posted·blocked·waiver_pending·cancelled), approval_id FK NULL, client_ref UQ, created_by, created_at |

### 4.7 Production & outbound

| Table | Columns |
|---|---|
| `production_confirmations` | id, order_id FK, line_id FK, shift CHECK(A·B), material_id FK, good_qty, rejected_qty, reject_reason_id FK NULL (required if rejected_qty>0 — service-enforced), downtime_min, downtime_reason_id FK NULL, process_loss JSONB ({blanking,piercing,forming}), kind CHECK(interim·shift_close), status CHECK(posted·corrected), client_ref UQ, supervisor_id FK, posted_at |
| `confirmation_corrections` | id, confirmation_id FK, delta_good, delta_reject, reason, approval_id FK, status |
| `dispatches` | id, doc_no (DN-…), customer_id FK, vehicle_no, total_pcs, status CHECK(open·invoiced·cancelled), client_ref UQ, created_by, created_at · `dispatch_lines`: id, dispatch_id FK, material_id FK, qty |
| `sales_invoices` | id, invoice_no, invoice_date, dispatch_id FK, irn NULL, eway_bill_no NULL, total_value, match_status CHECK(ok·mismatch), status CHECK(pending·confirmed), confirmed_by NULL, confirmed_at NULL, client_ref UQ · `sales_invoice_lines`: id, invoice_id FK, material_id FK, qty, value |

### 4.8 Workflow & system

| Table | Columns |
|---|---|
| `approvals` | id, approval_type CHECK(credit_waiver·debit_note·bom_yield·credit_rebaseline·confirmation_correction), ref_type, ref_id, payload JSONB, required_roles TEXT[], status CHECK(pending·approved·declined·hold), created_by, created_at, decided_at NULL |
| `approval_decisions` | id, approval_id FK, user_id FK, decision CHECK(approve·decline·hold), note, decided_at — co-approval = one row per required role |
| `anomalies` | id, rule_code, severity CHECK(hard·soft), ref_type, ref_id, observed JSONB, expected JSONB, message_en, message_mr, status CHECK(open·in_review·resolved), resolved_by NULL, resolved_at NULL, created_at |
| `notifications` | id, user_id FK, title, body, kind, ref_type, ref_id, read_at NULL, created_at |
| `audit_log` | id, at, request_id, user_id, role, station, device_key, method, path, entity, entity_id, action CHECK(create·update·status_change·decision·login·export), before JSONB NULL, after JSONB NULL — **INSERT-only: app DB role is granted INSERT but not UPDATE/DELETE on this table** |
| `sap_outbox` | id, record_type CHECK(GR·CONFIRMATION·ISSUE·DISPATCH·INVOICE), record_id, payload JSONB (frozen at write time), status CHECK(pending·batched·sent·acked·failed), batch_id FK NULL, attempts, last_error NULL, created_at, sent_at NULL |
| `sap_export_batches` | id, seq_no UQ, record_type, filename, row_count, checksum, status CHECK(building·uploaded·verified·acked·failed), created_at, uploaded_at NULL |
| `import_jobs` | id, kind CHECK(materials·boms·vendors·pos·schedule), file_id FK, status, rows_total, rows_ok, rows_failed, errors JSONB, created_by, created_at |

Indexes beyond PKs/FKs: `stock_ledger(material_id, location)`, `production_confirmations(line_id, posted_at)`, `line_plans(plan_date, line_id)`, `audit_log(entity, entity_id)`, `sap_outbox(status)`, `gate_entries(match_status) WHERE match_status='unmatched'`, `notifications(user_id) WHERE read_at IS NULL`.

---

## 5. Key mechanisms

### 5.1 Auth

Login (username/password or phone+OTP for vendors) → access JWT (15 min) + rotating refresh token (30 d, hashed in `auth_sessions`). JWT claims: `sub, role, station, vendor_id, device_key`. PIN quick-switch: only on a registered `station_device`, only for users whose station matches — exchanges PIN for a fresh token pair without full password. Every router is wrapped by a `require(*roles)` dependency; vendor-facing queries are *always* filtered by `vendor_id` from the token inside the service layer (scoping cannot be forgotten by a router).

### 5.2 Idempotency (what makes the retry queue safe)

Every mutating POST carries a client-generated `client_ref` UUID. Unique index → a retried request after a network timeout hits the constraint, and the API returns the original result with `200` instead of duplicating a confirmation or GR. This single convention is why "online-only + retry queue" is safe at a plant with patchy wifi.

### 5.3 Write path (uniform for every transaction)

One DB transaction containing: (1) validate input against current state → (2) run anomaly rules — hard violation aborts with a structured 422, soft violations collect → (3) write the domain row(s) → (4) write `stock_ledger` movements if stock changed → (5) write `sap_outbox` row with frozen payload → (6) write soft `anomalies` + `notifications` → commit. Audit middleware logs the before/after outside the service code. Either everything happens or nothing does — there is no state where a confirmation exists but its outbox entry doesn't.

### 5.4 SAP outbox state machine

`pending` →(batcher groups by record_type, assigns seq-numbered batch)→ `batched` →(CSV built: header, rows incl. our record IDs, trailer with row-count+checksum; SFTP upload as `*.tmp`, rename)→ `sent` →(ack file from SAP, if provided)→ `acked`, or →(error/timeout)→ retry with exponential backoff; after 5 failures → `failed` + admin notification. Worker claims work with `FOR UPDATE SKIP LOCKED`, so a crashed worker mid-batch resumes cleanly. Recovery from any crash point is at-least-once + SAP-side dedupe on record ID.

### 5.5 Anomaly rules

A registry: `RULES: list[Callable[[RuleContext], AnomalyResult | None]]`. MVP rules: `gr_qty_vs_po` (≥5× off → hard), `gr_qty_deviation` (>20% → soft), `confirmation_exceeds_plan` (>120% of remaining → hard), `rejection_spike` (>2× 30-day line baseline, recomputed nightly → soft), `invoice_dispatch_mismatch` (soft), `hsn_vs_material_group` (soft). Thresholds read from `app_settings`. Adding a rule = adding one pure function + one test.

### 5.5a Vendor exposure (the number behind credit limits)

MVP formula, in `services/inventory.py`: **credit exposure = Σ(AT_VENDOR stock qty × material price)** per vendor (our RM sitting at the vendor, valued at master price), and **qty position = Σ(AT_VENDOR qty in MT)**. Issues add to it; GRs of parts made from that RM relieve it (BOM-based relief). This matches the map's "RM stock at Yeshshree 7.2/10 MT" + "credit ₹12.45 L/₹14 L" screens. ⚠ Confirm with Yeshshree's Materials Head that this is how they compute it today — flagged in plan §10.

### 5.6 Approvals engine

Generic: anything needing sign-off creates an `approvals` row with `required_roles`. The inbox endpoint filters by the caller's role. When all required roles have approved, the engine calls the per-type `apply()` handler — `credit_waiver.apply()` posts the blocked issue, `debit_note.apply()` marks it raised, etc. Decline calls `reject()`. Handlers are small functions in `services/approvals.py`; new approval types don't touch the engine.

### 5.7 Scan pipeline

gate-agent (Python, packaged .exe; config = API URL + token + watch folder) detects a new ScanJet file → POST `/gate-entries/scans` (multipart, sha256; file remains locally until 200 received — a dead network never loses a scan). Server stores to R2, decodes with zxing-cpp: e-invoice QR → JWS payload (GSTIN, doc no/date, value, IRN); vendor-specific barcodes (TATA PDF417: PO no, vehicle, weight) → best-effort parse; HSN cross-check vs PO material group. Scan appears in the gate screen's pending list with whatever auto-filled; guard completes the rest. Decode failure → `decode_status='none'`, manual entry, image still archived.

### 5.8 Dashboards

Plain SQL aggregates in `services/dashboards.py` — achievement (line_plans ⋈ confirmations), sales (invoice_lines by day/MTD), yield (good vs rejected by line/shift/reason, scrap value via BOM+price), overview KPIs, anomaly register. Flutter polls every 30–60 s with ETag/`If-None-Match` so unchanged dashboards cost a 304. At pilot data volumes every query is single-digit milliseconds; materialized views are the documented escape hatch, not the default.

---

## 6. API inventory

All routes under `/api/v1`, JSON, OpenAPI auto-published at `/docs` (the Dart client is generated from this spec in CI).

| Router | Endpoints |
|---|---|
| `/auth` | POST login · refresh · logout · pin-switch · vendor-otp/request · vendor-otp/verify |
| `/master` | GET+admin-CRUD materials · vendors · boms · purchase-orders · lines · production-orders · customers |
| `/config` | GET/PUT splits · reason-codes · mills · calendar · settings (admin/planning only) |
| `/schedules` | POST upload → GET {id}/diff → POST {id}/release · GET list |
| `/plans` | GET line-plans?date&line · GET ppc-view · GET supervisor-view (line+shift) |
| `/gate-entries` | POST scans (agent) · GET scans/pending · POST decode-qr (phone) · POST create · GET unmatched · POST {id}/link-po · POST {id}/mark-consumable |
| `/goods-receipts` | POST create (from gate entry) · GET list/{id} |
| `/issues` | POST create (returns posted | blocked+approval_id) · GET list |
| `/confirmations` | POST create (interim/close) · GET history?line&date · POST {id}/correction |
| `/dispatches` | POST create · GET open |
| `/invoices` | POST create · POST {id}/confirm · GET list |
| `/approvals` | GET inbox · POST {id}/decide |
| `/anomalies` | GET register · POST {id}/resolve |
| `/dashboards` | GET overview · achievement · sales · yield · vendor-summary |
| `/vendor` (vendor-scoped) | GET my-schedule · my-pos · my-account · my-stock |
| `/notifications` | GET list · POST {id}/read |
| `/imports` | POST upload?kind · GET jobs/{id} |
| `/exports` | GET reconciliation?date&type · GET sap-batches |
| `/system` | GET healthz · GET version |

Error envelope (uniform): `{"error": {"code": "CREDIT_LIMIT_BREACH", "message_en": …, "message_mr": …, "details": {…}}}` — stable machine codes so the Flutter app switches UI on `code`, never on message text, and Marathi comes from the same response.

---

## 7. Environments, deployment, operations

**Local:** `docker-compose up` = Postgres + MinIO (S3-compatible stand-in for R2) + api + worker; `make seed` loads the real SAP exports; `make repro` = compose + seed + smoke test. The whole system on a laptop in one command — the AI-debuggability cornerstone.

**Prod (Railway/Render):** `api` + `worker` from one image, managed Postgres, R2. Deploy = git push → CI (pytest, alembic upgrade dry-run, OpenAPI/ERD freshness check) → migrate → release. Staging = optional second environment, same recipe.

**Migrations:** Alembic, autogenerate + human/AI review; applied migrations are immutable; every migration reversible or explicitly marked not.

**Backups:** platform daily snapshots + nightly `pg_dump` shipped to R2 (30-day retention) + R2 object versioning for files. Restore drill documented in the runbook and rehearsed once before pilot.

**Observability:** structlog JSON logs with `request_id` (also stored on audit rows — one ID ties a user action to its logs); `/healthz` (DB + storage + outbox backlog); alert = notification + email to admin when outbox has `failed` rows or backlog > threshold. Sentry optional, one env var.

**Secrets:** platform env vars only (DB URL, JWT key, R2 keys, SFTP creds). Nothing in the repo; `.env.example` documents every variable.

---

## 8. Testing strategy

| Layer | What | How |
|---|---|---|
| Parsers | SAP TSV importers, schedule parser, QR/PDF417 decode | Golden-file tests against the real files in `data/` (incl. the 3 real scans) |
| Services | limit checks, anomaly rules, plan math, outbox batching, approvals | pytest against a real Postgres (docker), factory fixtures |
| API | every endpoint: auth, validation, idempotent retry, vendor scoping (vendor A must 404 on vendor B's data) | httpx TestClient |
| End-to-end | one scripted "thin slice": schedule → release → gate scan → GR → issue → confirm → dispatch → invoice → dashboards reflect all of it | runs in CI on every push; doubles as the living spec |
| Outbox | kill the worker mid-batch, assert no loss & no dupes after restart | dedicated chaos test |

CI gate: tests + `alembic check` + OpenAPI/ERD freshness. Definition of done per milestone additionally requires both doc tracks updated (plan §9).

---

## 9. Capacity & limits (honest numbers)

~100 concurrent users, dashboard polling ≈ 3–5 req/s sustained, write peaks (shift close) ≈ 1–2 req/s. Yearly data: confirmations ~50k rows, ledger ~200k, audit ~2–5M (largest table; partition by month *if* it ever matters), scans/photos ~15k files ≈ 5–8 GB. Smallest managed Postgres + 512 MB API container is ~10× headroom. The documented upgrade path: bigger instance → read replica for dashboards → websockets. Step 1 will likely never be needed; steps 2–3 are listed so nobody invents Kafka in year two.

## 10. Out of scope here

UI architecture (Flutter state management, navigation, offline retry queue client-side) — next planning session. SAP postback CSV column spec + ack format — blocked on SAP team (plan §10 item 1a). Real SMS OTP, FCM push, OCR, BAPI — phased per plan §8.

## 11. Premortem hardening (v2 deltas)

Each delta maps to a §9 item in `Yeshshree_Failure_Scenarios.md`; milestone in the heading. All new enums are TEXT + CHECK; all stock effects go through `stock_ledger`; all mutating endpoints carry `client_ref`.

### 11.1 Parallel-run stock policy — `ops_mode` (§9-1, M3)

`app_settings` key `ops_mode`: `{"mode": "parallel_run"}` — CHECK in service: `parallel_run·authoritative`. `services/inventory.py::check_stock()` reads it on every issue/dispatch: in `parallel_run`, insufficient/negative stock returns a **warning** (soft anomaly `stock_insufficient_warned` + posts anyway, `limit_check` snapshot records the warn); in `authoritative` it hard-blocks as designed. Stock reconcile: `import_jobs.kind` += `sap_stock`; importer diffs SAP snapshot vs `stock_balances` per material × location and writes `stock_ledger` `ADJUST` rows (`ref_type='import_job'`, `ref_id`=job) — fully audited, never an UPDATE. Upload via existing `POST /imports/upload?kind=sap_stock`.

### 11.2 Approval delegates, SLA, emergency override (§9-2, M3)

| Table | Columns |
|---|---|
| `approval_delegations` | id, principal_user_id FK, delegate_user_id FK, approval_type NULL (NULL = all types), valid_from, valid_to, created_by, is_active |

Inbox query expands `required_roles` through active delegations (validity window checked at decision time, not grant time); `approval_decisions` gets `on_behalf_of_user_id FK NULL`. SLA reminders/escalation ride the generic engine (§11.8 rules `approval_pending_2h`, `approval_pending_4h` → remind approvers, then escalate to MD/management).

**Emergency override:** `POST /approvals/{id}/override` (role management/admin). Body: mandatory `reason`. Effects in one transaction: approval `status='overridden'` (CHECK extended), `overridden_by`, `override_reason` columns added; the per-type `apply()` runs (blocked issue posts); a **new** `approvals` row `approval_type='override_review'` is auto-created with the original `required_roles` (post-facto sign-off); blocker notification to those roles. `GET /dashboards/overview` adds `open_override_reviews` count — overrides are never invisible.

### 11.3 Offline gate fallback + backfill (§9-3, M2)

Client queues a **minimal entry** locally when offline: `vehicle_no, driver_name, vendor_name_text (free text), entered_at, vehicle_photo, doc_photo, client_ref`. Trucks proceed; paper register continues.

`POST /gate-entries/backfill` accepts the minimal set → creates a gate entry with `entry_mode='backfill'`, `backfill_status='pending_completion'`, `match_status='unmatched'`. New `gate_entries` columns: `entry_mode CHECK(live·backfill) DEFAULT 'live'`, `backfill_status NULL CHECK(pending_completion·completed)`, `vendor_name_text NULL`. `POST /gate-entries/{id}/complete-backfill` fills vendor/PO/invoice → `completed`. GR is blocked until completion; pending backfills surface in the unmatched folder.

### 11.4 gate-agent heartbeat + station status (§9-4, M2)

`POST /system/agent-heartbeat` (agent service token, every 60 s): `{device_key, agent_version, watch_folder_ok, last_scan_at}`.

| Table | Columns |
|---|---|
| `station_status` | id, device_key UQ, kind CHECK(gate_agent·station_app), last_heartbeat_at, agent_version, detail JSONB |

`GET /system/station-status` — gate screen polls it; heartbeat older than 5 min → banner "scanner offline since HH:MM" with one-tap fallback (phone QR / manual). Older than 15 min → escalation rule `gate_agent_stale` notifies admin (§11.8).

### 11.5 Gate `doc_type` + `inward_category` + invoice-later (§9-5, M2)

`gate_entries` += `doc_type CHECK(invoice·challan·return_gatepass·other_inward) DEFAULT 'invoice'`, `inward_category NULL CHECK(po_supply·customer_return·consumable·repair)`. `invoice_no/invoice_date/invoice_value` become nullable when `doc_type≠'invoice'` (service-enforced). **Invoice-later rule:** challan entries GR normally (stock posts on GR as always); billing linkage waits — `POST /gate-entries/{id}/attach-invoice` (invoice_no, date, value, optional scan) any time after; debit-note drafting against a challan GR defers `base_amount` valuation to master price until invoice attaches. `customer_return`/`repair` need no vendor/PO; stock posting stubbed out in MVP (category recorded, lifecycle phase 2 per §9 accepted-out list).

### 11.6 Part-consignment continuation (§9-6, M2)

`gate_entries` += `consignment_no SMALLINT DEFAULT 1`, `consignment_total SMALLINT NULL`. Uniqueness changes from "warn on duplicate vendor+invoice_no" to partial unique index `UQ(vendor_id, invoice_no, consignment_no) WHERE doc_type='invoice'`. Duplicate detection response becomes a structured 409 offering explicit continuation: client re-submits with `consignment_no=2, consignment_total=N`. Σ `qty_expected` across consignments is anomaly-checked against PO open qty (existing `gr_qty_vs_po` rule, evaluated cumulatively).

### 11.7 QC tolerances per material group (§9-7, M2)

| Table | Columns |
|---|---|
| `material_group_tolerances` | id, mat_group, uom, pct_tolerance NUMERIC(5,2), is_active, UQ(mat_group, uom) |

Admin-edited via `/config` (GET/PUT tolerances). `services/receiving.py` consults it **before** shortage/anomaly logic: `|received−expected|/expected ≤ pct_tolerance` → clean accept, `shortage_qty=0`, no flag; outside → existing shortage → 5× debit flow. Same lookup feeds `gr_qty_deviation` so in-tolerance steel GRs never soft-flag.

### 11.8 Generic escalation timers engine (§9-8, M3)

One scheduler mechanism in `services/escalations.py`; predicates are plain Python in a registry (code), thresholds and notify chains are config (DB):

| Table | Columns |
|---|---|
| `escalation_rules` | id, rule_code UQ, ref_type, threshold_min, notify_chain JSONB `[{after_min, roles[]}]`, repeat_min NULL, is_active |
| `escalation_events` | id, rule_code, ref_type, ref_id, stage, notified_roles TEXT[], created_at, resolved_at NULL, UQ(rule_code, ref_id, stage) |

Worker job `escalation_scan` (every 5 min, `FOR UPDATE SKIP LOCKED`): for each active rule, the registry predicate finds qualifying refs; unfired stages write `escalation_events` + tiered notifications. Resolution (GR posted, approval decided, entry matched) closes events. Seed rules: `gr_pending_30m` (gate entry open >30 min → store head; >2 h → management), `unmatched_gate_24h` (→ Purchase + planner, repeats daily), `hard_block_unanswered_30m` (open hard anomaly escalation → supervisor → store head → plant head, any may release), `approval_pending_2h` / `approval_pending_4h` (remind approvers+delegates → escalate MD), `gate_agent_stale_15m`. Adding a timer = one predicate function + one config row.

### 11.9 Full-lot rejection → return gate pass (§9-9, M2)

GR posted with `accepted_qty=0`, `qc_result='fail'` triggers in the same transaction: **no `stock_ledger` rows**; return gate-pass generated:

| Table | Columns |
|---|---|
| `return_gate_passes` | id, doc_no (RGP-…, new `doc_sequences` doc_type `RGP`), goods_receipt_id FK, gate_entry_id FK, vehicle_no, reason, status CHECK(issued·vehicle_left·cancelled), created_by, created_at |

`debit_notes.kind` CHECK += `full_lot_reject`; draft debit/return note auto-created (full invoice qty basis) → existing approval flow. Endpoint: `GET /goods-receipts/{id}/return-gate-pass` (printable payload for the guard).

### 11.10 Auto shift close + plan version pinning (§9-10, M4)

| Table | Columns |
|---|---|
| `shift_contexts` | id, line_id FK, shift_date, shift CHECK(A·B), plan_revision (line_plans.revision snapshot at open), opened_at, closed_at NULL, close_kind NULL CHECK(manual·auto), UQ(line_id, shift_date, shift) |

First confirmation of a shift opens the context, pinning the `line_plans` revision active **at shift start**. `confirmation_exceeds_plan` always validates against the pinned revision — mid-shift releases apply to future shifts only (release supersedes plans where `plan_date/shift` not yet opened). Worker job `shift_auto_close` fires at boundaries from `plan_calendar.shifts`: closes open contexts (`close_kind='auto'`), notifies the supervisor. `production_confirmations` += `shift_context_id FK`, `posted_after_close BOOL DEFAULT false` — late posts accepted, flagged, attributed by login.

### 11.11 "Can't confirm" PPC queue (§9-11, M4)

| Table | Columns |
|---|---|
| `confirmation_holds` | id, line_id FK, material_id FK, shift_context_id FK, payload JSONB (full confirmation body), status CHECK(open·resolved·discarded), resolved_order_id FK NULL, client_ref UQ, created_by, created_at |

`POST /confirmations` with no resolvable production order returns 409 + offers hold; `POST /confirmations/hold` stores it (nothing lost, nothing posted). `GET /plans/ppc-view` lists open holds with one-tap escalation (blocker notification to PPC). `POST /confirmations/holds/{id}/resolve` (PPC supplies `order_id`) posts the real confirmation from the payload, hold → `resolved`.

### 11.12 Issue corrections (§9-12, M3)

| Table | Columns |
|---|---|
| `issue_corrections` | id, issue_id FK, corrected JSONB (new material/qty/destination), reason, approval_id FK, status CHECK(pending·applied·declined) |

`POST /issues/{id}/correction` → `approvals` row (`approval_type` CHECK += `issue_correction`, required role: store head). `apply()`: reversing `ISSUE_OUT` ledger movement (negated qty, `ref_type='issue_correction'`) + new issue row posted with corrected values; original `issues.status` → `corrected` (CHECK extended). Never a silent edit.

### 11.13 Release sanity checks + rollback (§9-13, M1)

`POST /schedules/{id}/release` runs sanity checks, stored in `schedules.sanity JSONB`: period ≠ current month; Σ qty vs previous released version outside ±50%; unconfigured model family (existing hard stop, now names the config owner + deep-link). Warnings require `confirm_warnings: true` in the request body to proceed. **Rollback = re-release:** `POST /schedules/{id}/re-release` clones a superseded version as a new version (released), regenerates `line_plans`/`vendor_calloffs` as a new revision. Nothing is ever deleted; the bad release stays in history.

### 11.14 Notification tiers (§9-14, M6)

`notifications` += `tier CHECK(blocker·digest) DEFAULT 'digest'`, `acted_at NULL`, `next_repeat_at NULL`, `digest_of JSONB NULL`. Blockers (hard-block escalations, pending waivers blocking a truck, override reviews) repeat via worker job `blocker_repeat` (15 min: unacted blockers past `next_repeat_at` re-notify, backoff doubles); acting on the underlying ref sets `acted_at`. Everything else defaults to digest: worker job `digest_bundle` (hourly; daily for management) collapses unread digest rows into one summary notification carrying source ids in `digest_of`.

### 11.15 Admin & client hardening (§9-15, M0/M7)

- **Manual master add (M7):** `materials`/`vendors` += `source CHECK(sap_import·manual) DEFAULT 'sap_import'`. Existing admin CRUD allows create with `source='manual'` (temporary internal code). Importers reconcile: sap_code match → row adopted (`source='sap_import'`, diff audited); still-unmatched manual rows after import → soft anomaly `manual_master_unreconciled`.
- **Vendor credential reset (M7):** `POST /master/vendors/{id}/reset-credentials` (admin): update phone, revoke `auth_sessions`, issue fresh OTP via `otp_codes`.
- **Non-blocking photos (M0 pattern, M2 use):** gate entry posts without photos; `gate_entries.photos_pending BOOL DEFAULT false`; client retries `POST /gate-entries/{id}/photos` in background, server clears the flag on attach. Worker job `photos_pending_sweep` (nightly) flags entries pending >24 h to admin.
- **Version handshake (M0):** `GET /system/min-version` → `{min_version, latest_version, apk_url}`; app checks on launch, below minimum → force-update screen.
- **Clock-skew hint (M0):** every 401 error envelope includes `details.server_time`; client compares to device clock and shows "device clock is wrong" instead of "login failed" when skew > 2 min.

### 11.16 Milestone map

| M | Deltas |
|---|---|
| M0 | 11.15 (version handshake, clock-skew, photos-pending pattern) |
| M1 | 11.13 |
| M2 | 11.3, 11.4, 11.5, 11.6, 11.7, 11.9 |
| M3 | 11.1, 11.2, 11.8, 11.12 |
| M4 | 11.10, 11.11 |
| M6 | 11.14 |
| M7 | 11.15 (manual master add, vendor reset, pending-photo sweep) |

### 11.17 Invariants added

- Stock checks never hard-block while `ops_mode='parallel_run'`; reconciliation only ever writes `ADJUST` ledger rows — stock still only changes via `stock_ledger`.
- Every emergency override creates a post-facto `override_review` approval row and is visible on the management overview.
- A truck never waits on the app: minimal backfill entry is always acceptable at the gate; photos never block a post.
- Every escalation stage fires exactly once per ref (`UQ(rule_code, ref_id, stage)`); every timer lives in the one engine.
- Confirmations always validate against the plan revision pinned at shift start, never the latest.
- Full-lot rejection writes zero stock movements; corrections are always reversal + new row via approval, never an edit.
- Released schedules and superseded plan revisions are never deleted — rollback is a new release.
- No held confirmation is ever lost: `confirmation_holds.payload` preserves the full submission until PPC resolves or discards.
