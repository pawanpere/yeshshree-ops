# Admin guide — day-to-day administration

For Kartik as system admin. Everything here is what exists in the backend today;
where something is still pending, it says so.

## Users, roles, and stations

Roles: `admin`, `management`, `planning`, `plant_ops` (with station `gate`, `qc`,
`store`, or `ppc`), `supervisor`, `vendor`. The role decides which endpoints (and app
tiles) a user gets; the station decides which station device a plant_ops user can
PIN-switch on. There is no self-signup — every user is admin-created.

**Honest note:** there is no `/master/users` API endpoint yet. The seed creates 8 demo
users (password `demo1234`, PIN `1234`) — pilot onboarding replaces these. To add a
real user today, insert a row into `users` directly in the database. Generate the
password hash with:

    cd backend && python -c "from app.core.security import hash_password; print(hash_password('THE-PASSWORD'))"

Same helper for `pin_hash` (4-digit PIN). Set `role`, `station` (plant_ops only),
`language` (`en` or `mr`), and `is_active = true`.

## Registering a station device

Shared devices (gate, QC, store) must exist in `station_devices` before PIN quick-switch
works on them. The seed registers the pilot devices. A new device today is also a manual
SQL insert: `device_key` (unique, e.g. `gate-tab-1`), `station`, `label`,
`registered_by` (your user id), `is_active = true`. PIN switch only works when the
user's station matches the device's station. The gate scanner PC uses a `device_key`
too (in `agent.ini`) — it shows up on the station-status panel via its heartbeat.

## Resetting a vendor's login

The planned endpoint `POST /master/vendors/{id}/reset-credentials` is **not built yet**
(it ships with the vendor portal, P37, which is post-pilot). For now: update the phone
number on the vendor's user row, and revoke their sessions by setting `revoked_at` on
their rows in `auth_sessions`. OTP login is mock in MVP — the dev code is returned in
the API response, no real SMS yet.

## Editing config

All config is under `/config` endpoints (admin/planning), and every change is audited.

- **Splits** — Yeshshree/Laxmi percentage per model family. **Must total 100.**
  Effective-dated; history is immutable (you add a new effective-from row, never edit).
- **Reason codes** — reject and downtime codes. Both `label_en` and `label_mr` are
  required; supervisors see the Marathi label. Deactivate, never delete.
- **Tolerances** — per material group + unit (steel: 0.5%). GRs inside tolerance accept
  cleanly; outside triggers the shortage/debit flow. Edit with the QC lead's agreement.
- **Calendar and shifts** — working days and the plant-default shift times, set per
  month with a bulk PUT. Lines can carry their own `shift_pattern` override (shifts
  vary by line at Yeshshree); auto shift-close honors the per-line pattern.
- **Settings** — anomaly thresholds, debit multiplier (5×), GR target minutes, and
  `ops_mode`. **Flipping `ops_mode` from `parallel_run` to `authoritative` is a
  business decision, not a technical one** — it makes stock checks hard-block the
  floor. The flip is audited with who did it. Do not flip it without management.

## Seeding and resetting pilot data

- `make seed` — loads the real SAP exports (194 materials, 7 BOMs, real vendors, POs)
  plus pilot config. Idempotent: safe to re-run, it upserts by key.
- `python -m app.importers.seed --reset` — drops and recreates everything first.
  **Dev only. Never run with `--reset` against the pilot database.**

## Watching the system

- **Anomaly register** — `GET /anomalies`. Soft anomalies (deviations, mismatches)
  accumulate here; review and resolve them (`POST /anomalies/{id}/resolve`). Open hard
  anomalies are blocking someone — treat them as urgent.
- **Escalations** — run automatically every 5 minutes: GR pending 30 min, unmatched
  gate entry 24 h, unanswered hard block 30 min, approval pending 2 h/4 h, gate agent
  stale 15 min. They resolve themselves when the underlying thing is done.
- **Notifications** — blockers repeat with doubling backoff until acted on; everything
  else is bundled into hourly digests (daily for management).
- **Override reviews** — every emergency override opens one. The overview dashboard
  shows the open count; chase them to zero.

## Manual master-data adds

If a material or vendor is needed before SAP has it, create it via the admin CRUD —
it is stamped `source='manual'`. When the next SAP import runs, rows matching by SAP
code are adopted (`source` flips to `sap_import`, diff audited). Manual rows still
unmatched after an import raise a soft anomaly `manual_master_unreconciled` — fix the
code or retire the row. Master data is never deleted, only deactivated.

## Uploading the SAP stock snapshot

`POST /imports/sap-stock` (admin/planning) with the SAP stock report file. The importer
diffs SAP's balances against the app's per material × location and writes **ADJUST**
ledger rows for the differences — fully audited, never an edit of balances. Do this
periodically during the parallel run to keep app stock honest against SAP.
