# Yeshshree Operations App — MVP Backend Plan (v1)

Date: 10 Jun 2026 · Owner: Kartik · Status: agreed in planning session, pending Bajaj schedule sample

---

## 1. Decisions log

| # | Decision | Choice |
|---|----------|--------|
| 1 | Backend stack | FastAPI (Python 3.12) + PostgreSQL 16 + SQLAlchemy 2 + Alembic. Chosen for AI-maintainability: all logic in one greppable codebase, best AI training coverage, auto-generated OpenAPI spec. |
| 2 | Frontend | Flutter — one codebase for Android APK + Web (management/planning dashboards). |
| 3 | Hosting | Railway or Render for MVP (~$5–10/mo, git-push deploy, managed Postgres). Everything Docker — portable to AWS Mumbai / plant server later. |
| 4 | SAP sync | SAP team will provide CSVs via SFTP (later). MVP runs on seed data imported from the real SAP exports already in this folder + mock transactional data. SFTP job is a thin add-on later. |
| 5 | Offline | Online-only + client-side retry queue for failed posts. Re-assess after pilot starts. |
| 6 | MVP scope | Thin end-to-end slice: all 8 pipeline stages work for 5–10 pilot parts. Intelligence modules deferred (see §8). |
| 7 | Auth | Username/password for internal users (admin-created, no self-signup). Vendors: phone + mock OTP (fixed/displayed code), real SMS later. PIN quick-switch on shared station devices. |
| 8 | Pilot mode | Parallel run — SAP + paper continue as today; app entries are compared via reconciliation exports to build trust. App bugs cannot stop the plant. |
| 9 | Devices | Mix: shared Android device per station (gate, QC, store) + personal phones (supervisors, managers, vendors). |
| 10 | Schedule ingest | Kartik will add a real Bajaj schedule sample to the folder; import is designed against it. Until then, a mock format based on the sale report parts. |
| 11 | Language | English + Marathi. Flutter i18n (ARB) from day one; reason codes carry `label_en` + `label_mr` in the DB. |
| 12 | Photos | Gate captures vehicle + invoice photos via phone camera. Stored in S3-compatible storage (Cloudflare R2 free tier); local-disk driver for dev. |
| 13 | Scanning | HP ScanJet at the gate, confirmed. Flow: guard scans invoice → watched folder on gate PC → watcher agent uploads to API → **server decodes barcodes from the scanned image** (zxing-cpp — no OCR) → auto-fill → PO match → gate screen confirmation. **Validated 10 Jun 2026 on the 3 real scans in this folder:** TATA = e-invoice QR (GSTIN, invoice no, date, value, IRN) **+ PDF417 barcode containing the SAP PO number, vehicle no, and weight** → fully automatic. JSW = e-invoice QR decoded → vendor+invoice auto-fill, guard picks PO from vendor's open-PO list. POSHS (small vendor) = no barcodes → manual key-in fallback, which therefore stays first-class. Full-page OCR of line items deferred to phase 2, only if non-QR vendor volume justifies it. |
| 14 | Audit ("like SAP") | Every write captures actor, role, station, device, timestamp, entity, and field-level before/after (mirrors SAP change documents CDHDR/CDPOS). Append-only — no updates or deletes on the audit table. Event timestamps also drive process KPIs (e.g. gate→GR minutes vs the 30-min target). |
| 15 | Documentation | Dual-track docs in-repo, updated as part of every milestone's definition of done: `docs/human/` for people, `CLAUDE.md` + `docs/ai/` for AI agents. Details in §9. |

---

## 2. Architecture

```
Flutter app (Android + Web)
   │  REST/JSON (Dio client generated from OpenAPI spec)
   ▼
FastAPI  ──  JWT auth, role guards, vendor scoping
   │         domain services (limits, validations, approvals, plan math)
   ▼
PostgreSQL 16  ──  single instance, Alembic migrations
   │
   ├── Object storage (R2/S3 driver) — gate photos
   ├── Import jobs — SAP export parsers (UTF-16 TSV, already verified against real files)
   └── Export jobs — daily reconciliation CSVs (app vs SAP parallel-run compare)
```

No microservices, no message queue, no Kubernetes. 500–1000 users ≈ 50–100 concurrent ≈ trivial load for one API container + one Postgres. "Live" dashboards poll every 30–60 s in MVP (simple, debuggable); websockets only if polling ever feels slow.

### Repo layout (monorepo)

```
yeshshree-ops/
├── backend/
│   ├── app/
│   │   ├── api/            # routers, one file per domain (gate.py, confirmations.py …)
│   │   ├── models/         # SQLAlchemy models
│   │   ├── schemas/        # Pydantic request/response
│   │   ├── services/       # business logic (limits.py, anomaly.py, approvals.py, plans.py)
│   │   ├── importers/      # SAP export parsers + seed
│   │   └── core/           # auth, config, deps
│   ├── alembic/
│   ├── tests/              # pytest, per domain
│   └── Dockerfile
├── app/                    # Flutter (mobile + web), l10n/ with en + mr ARB files
├── gate-agent/             # ~100-line Python watcher for the gate PC: watches ScanJet
│                           # output folder → uploads scans to the API. Packaged as .exe.
├── data/                   # the SAP exports + Bajaj schedule sample + mock generators
├── docs/                   # this plan, screen→endpoint map, runbook
└── docker-compose.yml      # postgres + api + minio(dev) — full system locally in one command
```

---

## 3. Data model (~30 tables)

### Master data (seeded from the real SAP exports in this folder)

| Table | Key fields | Source |
|-------|-----------|--------|
| `materials` | sap_code, description, type (ROH/HALB/FERT), group, uom, price | `1117 material code list.xls` |
| `boms` / `bom_lines` | parent material, component, qty_per, uom (incl. negative scrap-credit lines) | `1117 bill of material.xls` |
| `vendors` | sap_vendor_code, name, gstin, phone, city, credit_limit, qty_limit_mt | `vendor list.xls` |
| `purchase_orders` | sap_po_no, vendor, material, qty, open_qty, rate, due_date | `1117 purchase report.xls` + mock |
| `lines` / `line_parts` | line name (Front Body, Side Panel LH/RH, Floor Top), plant, allowed materials | app map |
| `production_orders` | sap_order_no, line, material, status | mock (per app map: 100482–100485) |
| `users` | username, password_hash, pin_hash, full_name, role, station, vendor_id?, language | admin-created |
| `station_devices` | device_id, station, allowed roles | registered shared devices |

### Config (Planning's §5.11 screen — versioned, audited)

`model_family_splits` (family, yesh_pct, laxmi_pct, effective_from) · `reason_codes` (type reject/downtime, code, label_en, label_mr, active) · `mills` (name, lead_days, moq_mt, sourcing type) · `plan_calendar` (date, working_day, shifts — drives plan dates + the shift suggestion on the supervisor's pick screen) · `app_settings` (thresholds: anomaly %, debit multiplier 5×, GR target minutes).

### Transactions

| Table | Notes |
|-------|-------|
| `schedules` + `schedule_lines` | Bajaj schedule: period, version, status draft/released, diff computed vs previous version. Format locked when sample file arrives. |
| `line_plans` | per date × line × material: planned qty. Generated on release (simple math in `services/plans.py`, NOT the full cascade engine). Feeds PPC view, supervisor plan, achievement dashboard. |
| `vendor_calloffs` | per vendor × material × date: qty (what the vendor schedule screen shows). |
| `gate_entries` | G-numbers; vendor, invoice_no/date, matched PO?, material+qty (locked from PO when matched), vehicle, driver, photo refs, status matched/unmatched/consumable. |
| `goods_receipts` | GR-numbers; from gate entry; expected vs received qty, pass/fail, rejected_qty (separate), shortage → auto-draft debit note. |
| `debit_notes` | 5× shortage drafts → approval flow. |
| `stock_ledger` | append-only: every GR / issue / confirmation / dispatch writes a movement; balances are a view. Single source for stock + days-of-cover. |
| `issues` | destination in-house line / sale to vendor / job work; qty + value; limit check result; status posted/blocked/waiver_pending. |
| `production_confirmations` | order, line, shift, material, good_qty, rejected_qty (+reason code), downtime_min (+reason), process_loss JSON (blanking/piercing/forming), type interim/shift_close, supervisor, timestamps. The hero table. |
| `confirmation_corrections` | post-close fixes via approval, never silent edits. |
| `dispatches` + `dispatch_lines` | DN-numbers; customer, vehicle, parts+qty. |
| `sales_invoices` + `invoice_lines` | invoice no, date, IRN + e-way bill (manually keyed text in MVP), match-check vs dispatch qty, status pending/confirmed. Feeds live sales report. |

### Workflow & system

| Table | Notes |
|-------|-------|
| `approvals` | type (credit_waiver, debit_note, bom_yield, credit_rebaseline), payload JSON, source ref, required roles, decisions log. One generic engine for all four MVP approval types. |
| `anomalies` | rule, severity hard/soft, ref, value vs expected, status. MVP rules in §5 below. |
| `notifications` | in-app inbox per user (FCM push deferred). |
| `audit_log` | SAP-style change documents: actor, role, station, device_id, entity, action, field-level before/after JSON, timestamp. Append-only (DB role has INSERT only — no UPDATE/DELETE). Written automatically by a FastAPI dependency on every mutating endpoint, so no endpoint can forget it. Doubles as the source for per-user/station activity and timing KPIs (gate→GR turnaround, confirmations per shift). |
| `sap_outbox` | **Guaranteed postback (transactional outbox).** Every GR / confirmation / invoice / issue write inserts an outbox row in the same DB transaction. Worker batches pending rows → CSV → SFTP, marks `sent` only after verified upload. Failed rows stay pending, retry with backoff, alert after N failures. Table exists from M2; SFTP worker activates when SAP credentials arrive. |
| `import_jobs` / `export_batches` | file imports with row-level error logs; export batches are sequence-numbered, never reused; daily reconciliation CSV for the parallel run. |

---

## 4. API surface (~50 endpoints, grouped)

`/auth` login, refresh, PIN quick-switch, mock-OTP for vendors · `/master` materials, BOMs, vendors, POs, lines (+ admin CRUD) · `/config` splits, reason codes, mills, settings · `/schedules` upload, diff, release · `/plans` line plans by date/line, PPC + supervisor views · `/gate-entries` create (+photo upload), unmatched folder, link-PO · `/goods-receipts` create from gate entry, QC decision · `/issues` create with limit-check, waiver request · `/confirmations` create interim/close, history, corrections · `/dispatches`, `/invoices` create, confirm-sale · `/approvals` inbox, decide · `/dashboards` overview, achievement, sales, yield, anomalies (SQL aggregates over the ledger + confirmations) · `/notifications` · `/imports`, `/exports` reconciliation.

Every endpoint typed with Pydantic → OpenAPI → generated Dart client. Vendor-scoped endpoints filter by `vendor_id` from the JWT — a vendor can never query another vendor's data.

---

## 5. Business rules in MVP (the deliberately small version)

**Limit check at issue (§5.7):** on `POST /issues` with vendor destination, compute vendor's open balance + qty position from the ledger. Qty or credit breach → block, create approval (credit_waiver, Materials Head + CFO), notify. Approval → issue auto-posts.

**Anomaly checks (§5.8, simple rules not an "engine"):** hard-block when received qty is ≥5× off PO open qty or a confirmation exceeds remaining plan qty by >20%; soft-flag when received qty deviates >20% from expected or shift rejection rate >2× the 30-day line baseline. Hard = refuse save, require re-type/escalate. Soft = save + register entry + notify supervisor. Rules are plain Python functions in `services/anomaly.py` with thresholds in `app_settings`.

**5× debit (Jun-2 rule):** GR shortage auto-drafts debit note = 5 × unit cost × short qty → approval inbox.

**Plan math (replaces cascade engine in v1):** release schedule → apply family split % from config → explode via BOM for RM/component view → write `line_plans` + `vendor_calloffs`. Linear, transparent, testable. No drift detection, no mill flags, no auto-recascade.

**Dispatch↔invoice match:** invoice confirm checks Σ invoice qty = Σ dispatch qty per part; mismatch → soft-flag + warning, allowed with reason.

**Guaranteed SAP postback (outbox pattern):** delivery = at-least-once + dedupe, never at-most-once. Atomic SFTP upload (`*.tmp` → rename), sequence-numbered filenames, row-count/checksum trailer, unique record IDs in every row so SAP-side import can skip duplicates. Open question for SAP team: can they return an ack/error file via SFTP? If yes, the loop closes automatically; if no, the daily reconciliation report is the safety net.

**Invoice scan at gate (ScanJet pipeline):** scan → gate-agent uploads to `POST /gate-entries/scans` → server stores the image and decodes the GST e-invoice QR from it (signed JWS payload: seller GSTIN, doc number/date/value, IRN) → vendor lookup by GSTIN → auto-fill → match open POs → entry appears in the gate screen's "pending scans" list for the guard to confirm vehicle/driver. No OCR involved for the core fields. Fallbacks: phone-camera QR scan (`POST /gate-entries/decode-qr`) and manual key-in (vendors below the e-invoicing threshold have no QR — e.g. the POSHS sample). Gate-agent retries on network failure; scans are never lost (files stay in the folder until upload is acknowledged). Material descriptions/codes/rates are never read from paper — they come from the PO → material-master join (same join SAP's own GRN report does). The QR's HSN code is used as a cheap anomaly cross-check against the matched PO's material group.

---

## 6. Auth model

Internal: username/password → JWT (access 15 min / refresh 30 d). Shared station devices register once; users on them re-enter only a 4-digit PIN to switch accounts (full password if PIN unset). Vendors: phone + OTP where MVP "sends" a fixed dev code (shown in admin panel) — swapped for MSG91/Twilio later without API changes. Roles: `admin, management, planning, plant_ops(gate|qc|store|ppc), supervisor, vendor` — FastAPI dependency guards per router; station controls which home tiles the app shows.

---

## 7. Milestones (build order — each one demoable)

| M | Scope | Backend deliverables |
|---|-------|---------------------|
| **M0** | Foundation | Monorepo scaffold, docker-compose, CI (pytest + flutter analyze), Alembic baseline, auth (login/JWT/PIN/mock-OTP), audit middleware, **seed importer from the 5 real SAP files**. |
| **M1** | Plan in | Master + config CRUD, schedule upload→diff→release, plan math, line-plan/PPC endpoints. (Schedule parser finalized when sample file lands.) |
| **M2** | Inward | Gate entry + photo upload + PO auto-match, **gate-agent (ScanJet watcher) + server-side QR decode from scans**, unmatched folder, GR/QC with pass/fail + separate rejects, 5× debit draft, anomaly checks v1. Tested against the 3 real scanned invoices in `data/`. |
| **M3** | Issue & stock | Stock ledger, issue with limit checks, waiver → generic approvals engine, approvals inbox API. |
| **M4** | Production (hero) | Production confirmations interim/close, history, corrections, achievement + yield dashboard queries. |
| **M5** | Outbound | Dispatch, invoice + confirm-sale, live sales dashboard, management overview, anomaly register. |
| **M6** | Vendor portal | Vendor-scoped: my schedule, my POs, my account & limits, stock-of-my-parts (read-only days-of-cover). Notifications inbox. |
| **M7** | Pilot hardening | Retry-queue semantics (idempotency keys on all posts), reconciliation CSV exports (app vs SAP parallel-run), Marathi ARB pass, seed/reset script, deploy + backups + runbook. |

Each milestone additionally absorbs its items from the premortem hardening list — see `Yeshshree_Failure_Scenarios.md` §9 (e.g. M2: gate offline fallback, agent heartbeat, doc_type, tolerances, full-lot rejection; M3: warn-don't-block stock policy, approval SLA/delegates/override, escalation timers).

Frontend tracks the same milestones (M1 planning web screens, M2 plant-ops phone screens, …). We build and demo milestone by milestone — no big-bang.

---

## 8. Explicitly deferred (post-MVP)

Cascade engine intelligence (drift detection, auto re-cascade, cascade preview) · auto-computed credit re-baseline proposals (planner proposes limits manually → same approval flow) · RM mill flags (§5.4) · supply-risk monitor + vendor one-tap ETA commitments + escalation (§5.12 — vendor sees read-only cover in MVP) · yield-engine BOM-factor proposals (§5.13 proposals; the yield *dashboard* IS in MVP) · scanner hardware + OCR (photo + manual key-in instead) · email/WhatsApp schedule auto-ingest · GST e-invoice IRN/e-way API integration (fields manually keyed) · vendor invoice auto-push by GSTIN (manual PO/invoice entry) · FCM push (in-app inbox first) · SFTP automation (manual upload screen first; parser identical) · offline-first sync · live BAPI SAP integration.

Each deferral has a v1 stand-in so every screen in the demo flow still works end-to-end.

---

## 9. Documentation strategy (dual-track, lives in the repo)

**For humans (`docs/human/`):** architecture overview in plain English with one diagram per flow (the 8 stages), a module guide per domain (what it does, which screens, which rules — written like the note-cards in the app map), an ops runbook (deploy, backup/restore, SFTP failure recovery, common errors), and an admin guide (creating users, config tables, resetting pilot data). Short, screenshot-led, Marathi glossary for shop-floor terms.

**For AI agents:** `CLAUDE.md` at repo root — project map, conventions, how to run/test/seed/debug, invariants ("audit_log is append-only", "stock only changes via stock_ledger", "outbox row in same transaction"). `docs/ai/decisions/` — one short ADR per decision in §1 so future agents know *why*, not just *what*. Auto-generated artifacts kept fresh by CI: OpenAPI spec, ER diagram from models, and a `make repro` target that boots the full system + seed data so an agent can reproduce any bug locally.

**Enforcement:** every milestone's definition of done = code + tests + both doc tracks updated. CI fails if OpenAPI/ERD artifacts are stale.

## 10. Open items

1. **Bajaj schedule sample** — Kartik adds to folder → locks `schedule_lines` format and the M1 parser.
1a. **SAP postback spec** — ask SAP team: exact CSV columns they expect per transaction type, SFTP folder structure, and whether they return ack/error files.
2. Pilot part list — confirm the 5–10 parts (suggest: the 4 mudguard assemblies from the sale report + their BOM components).
3. Confirm Laxmi (second Tier-1) is out of MVP scope — splits configured but only Yeshshree's share planned in-app.
4. Named pilot users per role (counts are enough for seeding).
5. Railway vs Render (both fine; decide at M0).
6. ~~Scanner hardware~~ — resolved: HP ScanJet at gate, gate-agent + QR-decode pipeline in M2. Remaining sub-question: is there a Windows PC at the gate with internet access for the agent?
7. Vendor credit-exposure formula — confirm with Materials Head: is exposure = value of RM lying at the vendor (issues − BOM-based relief on GRs), as designed in Architecture §5.5a?
