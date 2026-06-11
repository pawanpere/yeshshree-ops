# Runbook — running and operating the system

## Local dev (Kartik's machine)

    cp .env.example .env
    docker-compose up -d            # postgres + minio + api + worker
    make seed                       # load the real SAP exports + pilot config
    make verify                     # full gate: all tests + alembic check + openapi freshness + flutter
    make verify-lite                # sandbox-safe subset (SQLite, no docker)

API docs render at `/docs` once the api container is up. Note: `alembic upgrade head`
needs the baseline migration, which is **not yet generated** (see Known limits).

## Environment variables (.env.example)

| Variable | What it is |
|---|---|
| `DATABASE_URL` | Postgres connection string (psycopg). |
| `JWT_SECRET` | Token signing key — random, min 32 chars, never reuse dev value in prod. |
| `JWT_ACCESS_MINUTES` | Access-token lifetime (default 15). |
| `JWT_REFRESH_DAYS` | Refresh-token lifetime (default 30). |
| `S3_ENDPOINT` | Object storage endpoint (MinIO locally, R2 in prod). |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | Storage credentials. |
| `S3_BUCKET` | Bucket for scans, photos, imports/exports. |
| `OPS_MODE` | `parallel_run` or `authoritative` (mirrored in app_settings). |
| `APP_MIN_VERSION` / `APP_LATEST_VERSION` | Version handshake; below min → force-update screen. |
| `APK_URL` | Where the force-update screen sends users. |
| `SAP_SFTP_HOST` / `SAP_SFTP_USER` / `SAP_SFTP_KEY_PATH` | SAP SFTP. Blank until the SAP team provides them — the outbox worker stays idle without them. |

## The worker (`python -m app.worker`)

A plain loop, not Celery. Every job is idempotent; a crashed worker just restarts.
On startup it runs `recover_stuck` (see SFTP below).

| Job | Does | Interval |
|---|---|---|
| `outbox` | Batches pending outbox rows into CSVs, uploads via SFTP. | 5 min |
| `escalations` | Scans escalation rules, fires tiered notifications. | 5 min |
| `shift_auto_close` | Closes open shift contexts at shift boundaries (per-line patterns). | 5 min |
| `blocker_repeat` | Re-notifies unacted blocker notifications, doubling backoff. | 15 min |
| `digest_bundle` | Collapses unread digest notifications into one summary. | 1 h |
| `photos_pending_sweep` | Flags gate entries with photos pending >24 h (notify once). | 24 h |

## gate-agent install (gate PC)

1. Copy `gate-agent/agent.py` (or the packaged .exe — pyinstaller packaging on Windows
   is still pending) to the gate PC. Copy `agent.ini.example` to `agent.ini` and fill:
   `api_url`, `token` (service-account JWT, rotate via admin), `device_key`
   (e.g. `gate-scanjet-1`), `watch_dir` (the folder the ScanJet writes to, e.g. `C:\scans`).
2. Point the ScanJet at `watch_dir`. The agent uploads each finished scan and moves it
   to `watch_dir\uploaded\` **only after the server answered 200**. On any failure the
   file stays put and is retried forever with backoff — a dead network never loses a
   scan. The server dedupes identical bytes, so re-posts are safe.
3. The agent heartbeats every 60 s. If the gate screen shows the **"scanner offline
   since HH:MM" banner**, the server has not heard a heartbeat for 5+ minutes: check
   the gate PC is on, `agent.log` next to agent.py, and the network. At 15 minutes an
   escalation notifies admin. Guards fall back to phone QR scan or manual entry —
   trucks never wait.

## SFTP / outbox behaviour

- **No credentials yet:** the batcher is idle; outbox rows accumulate safely as
  `pending`. Nothing is lost; nothing needs doing.
- **After a crash:** batches stuck in `building` never went out. `recover_stuck` (run
  automatically at worker start) puts their rows back to `pending` and marks the batch
  failed. Delivery is at-least-once; SAP-side dedupe is on the record id.
- **`failed` rows** mean 5 upload attempts failed (`last_error` says why) and `/healthz`
  goes degraded. Fix the cause (network, key, host), then retry by setting the rows'
  status back to `pending` in `sap_outbox` — the next batcher pass picks them up.

## Health check

`GET /api/v1/system/healthz` returns `status` (`ok`/`degraded`), `db`, `storage`, and
`outbox` counts (pending/batched/failed). **Degraded means:** DB unreachable, storage
unwritable, or at least one `failed` outbox row. Pending rows alone are normal while
SFTP is unconfigured.

## Reconciliation export (the daily parallel-run compare)

`GET /api/v1/exports/reconciliation?on_date=YYYY-MM-DD&record_type=GR` (types: GR,
CONFIRMATION, ISSUE, DISPATCH, INVOICE) returns a CSV of everything the app captured
that day, built from the **frozen** outbox payloads — exactly what SAP was/will be
told, not today's mutable state. Compare it daily against SAP's own reports.
`GET /exports/sap-batches` lists uploaded batch files with row counts and checksums.

## Backup and restore

Production design: platform daily snapshots plus nightly `pg_dump` shipped to R2
(30-day retention) and R2 object versioning for files. **The restore drill has not
been rehearsed yet (P44)** — do it once before the pilot. Manual backup any time:
`pg_dump` against `DATABASE_URL`.

## KNOWN LIMITS (honest list, from the packet log)

- **Bajaj schedule parser is provisional** — built against a mock format; final form
  waits on the real sample file. Plan math interface is ready for either shape.
- **SAP postback CSV spec is pending** — column layout, folder structure, and ack
  handling need the SAP team. Until then the outbox CSV format is our own.
- **Baseline Alembic migration not yet generated** — human checkpoint on the dev
  machine, including the audit-log INSERT-only DB grant. The weighbridge and per-line
  `shift_pattern` columns land in it.
- **No users/station-device admin endpoints** — seed or SQL for now (see admin guide).
- **Vendor portal (P37) is post-pilot** — including vendor credential reset endpoint.
- **OTP is mock** (dev code shown, no real SMS); **push is in-app inbox only** (no FCM).
- **gate-agent .exe packaging** pending (runs as a Python script meanwhile).
- **Restore drill pending** (P44), and the first real CI run waits on a GitHub remote.
