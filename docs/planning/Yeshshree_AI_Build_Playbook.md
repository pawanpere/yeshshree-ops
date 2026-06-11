# Yeshshree — AI Build Playbook (Fable 5)

Companion to `Yeshshree_MVP_Backend_Plan.md`, `Yeshshree_Backend_Architecture.md` (v2 incl. §11 hardening), `Yeshshree_Failure_Scenarios.md`. Owner: Kartik. Date: 10 Jun 2026.

---

## 1. Why the architecture is shaped for AI builds

- **Monorepo** — backend, Flutter, gate-agent, data, docs in one tree; one agent session can see contract + both sides of any change.
- **One place for logic** — `api → services → models`, routers contain zero business logic; an agent looking for any rule has exactly one file to open (`services/*.py`).
- **OpenAPI → generated Dart client** — the contract is machine-checked; backend and Flutter packets can run in parallel against a frozen spec, and drift fails CI instead of debugging sessions.
- **Docker repro** — `make repro` boots Postgres + MinIO + api + worker + seed on any laptop; every bug an agent is asked to fix is reproducible in one command.
- **Tests-as-spec** — golden-file parser tests on real SAP exports/scans, the e2e thin slice, and per-rule pytest are the living spec; "done" is a green `make verify`, not an opinion.

## 2. Repo guardrails

### `CLAUDE.md` skeleton (repo root — every session reads this first)

```markdown
# Yeshshree Ops — agent guide
## Project map
backend/app/{api,services,models,schemas,importers,sap_sync,core}, backend/tests,
app/ (Flutter, l10n/ en+mr), gate-agent/, data/ (real SAP exports + 3 real scans),
docs/{human,ai/decisions}. Plan: docs/Yeshshree_MVP_Backend_Plan.md.
## Run / test / seed
docker-compose up            # postgres + minio + api + worker
make seed                    # load real SAP exports
make repro                   # compose + seed + smoke test
make verify                  # pytest + alembic check + openapi/client freshness + flutter analyze + flutter test
cd backend && pytest tests/<domain>/        # one domain only
## System invariants — NEVER violate, NEVER "optimize away"
1. audit_log is append-only (DB role: INSERT only). Audit is written by the FastAPI
   dependency on every mutating endpoint — never bypass or remove that dependency.
2. Stock changes ONLY via stock_ledger rows; balances are a view. No direct qty columns.
3. Every transactional write = ONE DB transaction: validate → anomaly rules → domain
   rows → stock_ledger → sap_outbox (frozen payload, same transaction) → soft
   anomalies/notifications → commit. No state where a row exists without its outbox row.
4. Every mutating POST has client_ref UUID UNIQUE; retry returns the original result (200).
5. Vendor scoping is enforced in the SERVICE layer from JWT vendor_id — never only in routers.
6. Corrections are new rows referencing the original (confirmations, issues). No silent edits.
7. Doc numbers come from doc_sequences under SELECT … FOR UPDATE only.
8. Applied Alembic migrations are immutable — new migration, never edit.
9. Statuses are TEXT + CHECK, money NUMERIC(14,2), qty NUMERIC(14,3), timestamptz everywhere.
10. Error envelope: {"error":{code, message_en, message_mr, details}} — Flutter switches on code.
11. Stock checks never hard-block while ops_mode='parallel_run'.
12. Every emergency override creates a post-facto override_review approval row.
## Conventions
See docs/ai/conventions.md. Decisions (the WHY): docs/ai/decisions/ADR-*.md.
```

### `docs/ai/conventions.md` (referenced, kept short)

Naming (snake_case tables, `doc_no` prefixes G-/GR-/ISS-/DN-/RGP-), one router/model/service/test file per domain, Pydantic schemas mirror endpoints, factory fixtures in `tests/factories.py`, structlog with `request_id`, Flutter: generated client only (never hand-written HTTP), ARB keys for every user-facing string.

### Never-do list for agents

- No business logic in routers; no raw SQL in `api/`; services never import from `api`.
- Never edit an applied migration; never use Postgres enums; never delete master-data rows.
- Never remove/skip the audit dependency or write outbox rows outside the domain transaction.
- Never hand-edit generated client code, the OpenAPI artifact, or `data/` golden files.
- Never weaken a test to make it pass; never touch files outside the packet's scope list.
- Never invent infra (Redis, Celery, websockets, microservices) — escape hatches are documented in Architecture §9.

## 3. The work-packet method

Every unit of work = one packet = one fresh agent session. One packet ≤ half a day of agent work, scoped so all needed context (CLAUDE.md + packet + 1–2 doc sections) fits comfortably.

```markdown
# Packet P-XX: <name>
Goal: one sentence, demoable.
Files in scope: explicit list (create/modify). Anything else = out of scope.
Contract: exact endpoints + request/response schemas, or table DDL, or screen↔endpoint map.
   Quote the relevant Architecture §4/§6/§11 rows verbatim.
Acceptance tests (write FIRST, watch them fail):
   - test names + the behaviour each asserts, incl. failure/edge cases and invariants
Out of scope: named adjacent things NOT to touch (and which packet owns them).
Verify: `make verify` green + packet-specific command (e.g. pytest tests/gate/ -x).
Docs: which docs/human + docs/ai files this packet must update.
```

## 4. Packet decomposition of M0–M7

| ID | Packet | Depends on | Acceptance criterion |
|---|---|---|---|
| P01 | Monorepo scaffold + docker-compose + Makefile | — | `make repro` boots api+worker+postgres+minio, `/healthz` 200 |
| P02 | CI pipeline (pytest, alembic check, openapi/client freshness, flutter analyze/test) | P01 | CI red on stale OpenAPI artifact, green on clean tree |
| P03 | Alembic baseline: all §4 tables, CHECKs, indexes, audit INSERT-only grant | P01 | `alembic upgrade head` + `alembic check` clean; grant test proves audit UPDATE fails |
| P04 | Auth core: login, JWT claims, rotating refresh, role guard dependency | P03 | Token pair issued/rotated; role-guard 403 tests pass |
| P05 | PIN quick-switch + station devices + vendor mock-OTP | P04 | PIN switch only on registered device with matching station; OTP verify issues vendor JWT |
| P06 | Audit middleware (before/after JSON, request_id) on every mutating route | P04 | Any POST writes audit row with actor/role/station/device; append-only enforced |
| P07 | SAP seed importers (UTF-16 TSV: materials, BOMs, vendors, POs) + `make seed` | P03 | Golden-file tests against the 5 real exports; row counts match |
| P08 | Outbox write-path helper + uniform write transaction + client_ref idempotency | P03,P06 | Duplicate client_ref returns original result 200; domain row never exists without outbox row |
| P09 | Flutter scaffold: generated Dio client, ARB en+mr, auth screens, role-based home tiles, version handshake + clock-skew message | P02,P05 | Login/PIN/OTP flows pass widget tests; below-min APK gets force-update screen |
| P10 | Master + config CRUD endpoints (admin/planning guarded, audited) | P06 | CRUD round-trips; config edits appear in audit_log; non-admin 403 |
| P11 | Schedule upload + parser + version diff (mock format until Bajaj sample) | P07 | Golden-file parse; v2 upload yields per-line diff vs v1 |
| P12 | Schedule release + plan math (splits → BOM explode → line_plans + vendor_calloffs) + sanity checks + rollback-by-re-release [§11.13] | P10,P11 | Release writes plans matching hand-computed fixture; ±50% warning fires; re-release supersedes, never deletes |
| P13 | Plan read endpoints: line-plans, PPC view, supervisor view | P12 | Views match seeded plan fixture by date/line/shift |
| P14 | Flutter planning web screens (upload, diff, release, PPC) | P09,P13 | Thin slice: upload→diff→release→plan visible, driven by generated client |
| P15 | Files service (R2/MinIO driver) + photo upload, non-blocking photos [§11.15] | P08 | Entry posts with photos pending; background retry attaches them |
| P16 | Gate entry create + doc_type (invoice/challan/other-inward) + part-consignment continuation [§11.5, §11.6] | P08,P15 | Challan entry posts without invoice no; duplicate invoice allows "part 2 of N" |
| P17 | Scan ingest + zxing decode (e-invoice QR, TATA PDF417) + HSN cross-check | P15 | Golden tests on the 3 real scans: TATA full auto-fill, JSW partial, POSHS manual |
| P18 | PO auto-match + unmatched folder + link-PO + re-link + aging alarm >24h [§11.8 rule] | P16 | Match locks material/qty from PO; re-link before GR; aged unmatched notifies purchase |
| P19 | gate-agent watcher (.exe) + heartbeat + station status banner [§11.4] | P17 | File survives kill/restart until 200 ack; missed heartbeat → banner + admin notification |
| P20 | GR/QC: pass/fail, tolerance config per material group, full-lot rejection + return pass, 5× debit draft [§11.7, §11.9] | P16,P18 | Within-tolerance accepts clean; shortage drafts 5× debit; full-lot reject touches no stock |
| P21 | Anomaly rules v1 + registry + register endpoint | P08 | Each §5.5 rule has a unit test; hard aborts 422, soft saves + registers |
| P22 | Flutter gate + QC screens + offline minimal-entry fallback + backfill screen [§11.3] | P09,P16,P20 | Airplane-mode entry queues locally; backfill completes it once online |
| P23 | Stock ledger writes + balances view + days-of-cover + ops_mode warn-don't-block + SAP stock reconcile import [§11.1] | P08 | Movements sum to view; insufficient stock warns, never blocks in parallel_run; reconcile import adjusts with audit |
| P24 | Issues + limit check (exposure = AT_VENDOR qty × price, qty MT) + waiver routing | P23 | Breach → blocked + approval created + notification; limit_check snapshot stored |
| P25 | Approvals engine: required_roles, inbox, decide, per-type apply/reject handlers | P08 | Co-approval needs all roles; apply() posts blocked issue; decline rejects |
| P26 | Approval SLA + delegates + emergency override + escalation timers engine [§11.2, §11.8] | P25 | Timers fire on fixture clock; override posts with mandatory reason + post-facto review approval |
| P27 | Issue corrections (reversal + reissue via approval) [§11.12] | P24,P25 | Correction nets ledger to true qty; original row untouched |
| P28 | Flutter store screens + approvals inbox (all roles) | P22,P24,P25 | Issue→block→waiver→approve→auto-post visible end-to-end in app |
| P29 | Production confirmations interim/close + plan version pinning at shift start [§11.10] | P08,P13,P23 | Reject qty requires reason; >120% of pinned plan hard-blocks; mid-shift plan cut doesn't block honest work |
| P30 | Auto shift close + late-post flag + "can't confirm" PPC queue [§11.10, §11.11] | P29 | Boundary auto-closes from plan_calendar; late post flagged; unresolved order lands in PPC queue |
| P31 | Confirmation corrections via approval | P25,P29 | Delta rows reference original; status `corrected`; no silent edit possible |
| P32 | Achievement + yield dashboard queries (ETag/304) | P29 | Numbers match hand-computed fixture; unchanged poll returns 304 |
| P33 | Flutter supervisor screens + client retry queue (client_ref, pending/posted history) | P28,P29 | Submit offline → queued → syncs once, no duplicate on retry |
| P34 | Dispatch + invoice + confirm-sale + qty match soft-flag | P08,P23 | Σ invoice qty ≠ Σ dispatch qty → soft-flag, allowed with reason |
| P35 | Overview + sales dashboards + anomaly register queries (incl. open_override_reviews KPI) | P21,P32,P34 | Drill-down from each KPI resolves to source rows |
| P36 | Flutter outbound + management dashboard screens | P33,P34,P35 | Dispatch→invoice→dashboard reflects within one poll cycle |
| P37 | Vendor-scoped endpoints (my-schedule/POs/account/stock) + admin credential reset [§11.15] | P12,P23,P24 | Vendor A gets 404 on vendor B's data (test required); reset re-issues OTP |
| P38 | Notifications inbox + blocker-vs-digest tiers [§11.14] | P25 | Blockers deliver immediately/repeat; FYIs bundle into digest |
| P39 | Flutter vendor portal + notifications UI | P33,P37,P38 | Vendor login shows only own scoped data, en+mr |
| P40 | Outbox worker: batcher, atomic SFTP (tmp→rename), seq/checksum, backoff, ack processor + chaos test | P08 | Kill worker mid-batch → restart → zero loss, zero dupes (chaos test in CI) |
| P41 | Reconciliation CSV exports + manual import screen (app-vs-SAP parallel run) | P23,P29,P34 | Daily export per type matches fixture; row-level import errors surfaced |
| P42 | Marathi ARB completion + error-code i18n completeness check in CI | P39 | CI fails on any error code or ARB key missing mr |
| P43 | Manual master-data add + importer reconciliation [§11.15] | P10 | Manual material usable immediately; next import adopts or flags it |
| P44 | Seed/reset script, deploy (Railway/Render), backups + restore drill, runbook | P40,P41 | Staging deploy green; documented restore rehearsed once |
| P45 | E2E thin slice in CI: schedule→release→scan→gate→GR→issue→confirm→dispatch→invoice→dashboards | P36 (all) | Full scripted slice green on every push; the living spec |

Milestone map: M0 = P01–P09 · M1 = P10–P14 · M2 = P15–P22 · M3 = P23–P28 · M4 = P29–P33 · M5 = P34–P36 · M6 = P37–P39 · M7 = P40–P45.

## 5. The loop (per packet)

1. **Spec** — paste the packet; agent restates contract + test list; human (Kartik) confirms in one message.
2. **Failing tests first** — agent writes the acceptance tests, runs them, shows them red. No implementation before red.
3. **Implement** — smallest code to green, inside the scope list only.
4. **`make verify`** — pytest + alembic check + OpenAPI/client freshness + flutter analyze + flutter test. Must be green locally before review.
5. **Self-review the diff** — agent walks its own diff against the never-do list and the invariants; flags anything it touched outside scope.
6. **Human review gate** — Kartik reviews diff + test names + doc updates; merges or returns with one correction message.

**Fresh session vs continue:** fresh session per packet, always. Continue the same session only for review corrections on that packet. If a packet runs long (context bloating, agent re-reading files, going in circles), stop, split the packet, restart fresh — never push a degraded session to "just finish".

## 6. CI gates (all blocking)

1. `pytest` (services, API, parsers, outbox chaos) against a real Postgres.
2. `alembic check` + upgrade dry-run (no model/migration drift).
3. OpenAPI artifact + generated Dart client freshness (regenerate, diff must be empty).
4. `flutter analyze` + `flutter test` (incl. widget tests).
5. Golden-file parser tests: 5 SAP exports + Bajaj schedule sample + the 3 real scans.
6. E2E thin slice (P45) on every push.
7. Error-code i18n completeness: every error code has `message_en` + `message_mr`; every ARB key in en exists in mr.
8. Doc-track check: milestone-closing PRs must touch `docs/human/` and `docs/ai/` (or declare why).

## 7. Human checkpoints — AI never decides alone

- **Migrations against prod** — agent writes them; only a human runs them.
- **Auth/permission changes** — roles, guards, vendor scoping, PIN/OTP flows: human review line-by-line.
- **Money-affecting rules** — credit/qty limits, exposure formula (pending Materials Head confirmation), 5× debit multiplier, tolerance percentages, anomaly thresholds in `app_settings`.
- **Anything touching the invariants list** (CLAUDE.md) — schema or behaviour changes to audit, ledger, outbox, idempotency, corrections.
- **Releasing/rolling back schedules and the parallel-run stock policy switch** (warn→block) — business calls, not code calls.
- Plus: deleting any data, changing CI gates, and the SAP postback CSV spec once it arrives.

## 8. Context hygiene for Fable 5 sessions

**Every session gets:** `CLAUDE.md`, the one packet, and the quoted/relevant sections of the planning docs (e.g. Architecture §4.6 + §5.3 for a ledger packet) — nothing more to start.

**Never load:** whole-repo dumps, unrelated domains' source, generated artifacts (Dart client, OpenAPI JSON), `data/` file contents (tests read them), or prior sessions' transcripts. The agent reads additional files on demand via search, not via bulk paste.

**Every session ends with:** green `make verify`, updated docs per the packet's Docs line, and the packet checklist (tests-first ✓, scope respected ✓, invariants untouched or flagged ✓, self-review done ✓) stated explicitly in the final message. A session that can't end green ends with a written handoff note in the packet, never a half-merged diff.
