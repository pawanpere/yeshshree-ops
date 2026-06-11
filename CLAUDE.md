# Yeshshree Ops — agent guide

Manufacturing operations app for Yeshshree Press Comps (plant 1117, Tier-1 to Bajaj).
FastAPI + PostgreSQL backend · Flutter (Android + Web) · gate-agent (Windows watcher).
Planning docs (read the section your packet quotes, not the whole thing):
`docs/planning/` — MVP plan, Backend Architecture v2 (§4 schema, §5 mechanisms, §6 API, §11 hardening), Failure Scenarios, AI Build Playbook (packets P01–P45).

## Project map

- `backend/app/api/` — routers. HTTP concerns ONLY: parse → call service → shape response.
- `backend/app/services/` — ALL business logic. One file per domain.
- `backend/app/models/` — SQLAlchemy models, one file per domain. `base.py` defines conventions.
- `backend/app/schemas/` — Pydantic request/response (source of OpenAPI).
- `backend/app/importers/` — SAP UTF-16 TSV parsers + seed.
- `backend/app/sap_sync/` — outbox batcher, SFTP, ack, reconciliation.
- `backend/app/core/` — settings, db, security, audit middleware.
- `backend/tests/` — pytest. Markers: `postgres` (needs real PG), default runs on SQLite.
- `app/` — Flutter. READ `app/ARCHITECTURE.md` FIRST: the 5 screen rules (S.t bilingual
  call-sites, ApiException handling, retry-queue for transactional POSTs with client_ref,
  direct reads, router contract). Current deviations + upgrade paths are in ADR-006
  (hand-written API calls until openapi-generator runs on the dev machine; S.t instead
  of ARB; shared_preferences until secure storage).
- `gate-agent/` — ScanJet folder watcher (P19).
- `data/` — golden files (real SAP exports + 3 real scanned invoices). NEVER edit.
- `docs/packets/` — one file per packet: spec, checklist, handoff notes.

## Run / test / seed

```
docker-compose up                  # postgres + minio + api + worker  (NOT available in Cowork sandbox)
make verify                        # FULL gate: pytest(all) + alembic check + openapi freshness + flutter analyze/test
make verify-lite                   # sandbox-safe subset: pytest -m "not postgres" on SQLite
make seed                          # load real SAP exports (P07)
make migration m="msg"             # alembic autogenerate inside docker — HUMAN runs and reviews
make openapi                       # export OpenAPI spec artifact
```

Environment split: Cowork sandbox has NO docker/postgres/flutter — it runs `verify-lite`.
Kartik's machine (ultracode) runs the full `make verify`. A packet is DONE only after full verify.

## System invariants — NEVER violate, NEVER "optimize away"

1. `audit_log` is append-only (DB role: INSERT only). Audit is written by the FastAPI
   dependency on every mutating endpoint — never bypass or remove that dependency.
2. Stock changes ONLY via `stock_ledger` rows; balances are a view. No direct qty columns.
3. Every transactional write = ONE DB transaction: validate → anomaly rules → domain rows
   → stock_ledger → sap_outbox (frozen payload, same transaction) → soft anomalies/notifications
   → commit. No state where a row exists without its outbox row.
4. Every mutating POST has `client_ref` UUID UNIQUE; retry returns the original result (200).
5. Vendor scoping is enforced in the SERVICE layer from JWT vendor_id — never only in routers.
6. Corrections are new rows referencing the original (confirmations, issues). No silent edits.
7. Doc numbers come from `doc_sequences` under SELECT … FOR UPDATE only.
8. Applied Alembic migrations are immutable — new migration, never edit.
9. Statuses are TEXT + CHECK (never Postgres enums), money NUMERIC(14,2), qty NUMERIC(14,3),
   timestamptz everywhere.
10. Error envelope: `{"error":{code, message_en, message_mr, details}}` — Flutter switches on code.
11. Stock checks never hard-block while `ops_mode='parallel_run'`.
12. Every emergency override creates a post-facto `override_review` approval row.

## Never-do list

- No business logic in routers; no raw SQL in `api/`; services never import from `api`.
- Never edit an applied migration; never use Postgres enums; never delete master-data rows.
- Never hand-edit generated client code, OpenAPI artifacts, or `data/` golden files.
- Never weaken a test to make it pass; never touch files outside your packet's scope list.
- Never invent infra (Redis, Celery, websockets, microservices) — escape hatches are in Architecture §9.

## Conventions

See `docs/ai/conventions.md`. Decisions and WHY: `docs/ai/decisions/ADR-*.md`.
Every session ends with: green verify(-lite here / full on machine), packet doc updated
(checklist + handoff), and docs touched per the packet's Docs line.
