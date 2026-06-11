# Waves 1–3: backend functionally complete — DONE (Cowork, 2026-06-13)
6 parallel agents (2 waves) + integrator. Suite: 122/122 verify-lite green. 90 endpoints.

## Wave 1
- P25/P26/P38 (agent D): approvals engine (co-approval per role, delegates w/ validity windows,
  decide-on-behalf, hold), §11.2 emergency override (mandatory reason → APPLY → auto
  override_review approval), §11.8 escalation engine (6 seeded rules, stage chains, UQ-safe
  rescans), notifications (blocker repeat w/ doubling backoff, digest bundling). 11 tests.
- P23/P24/P27 (agent E): stock balances/days-of-cover, §11.1 ops_mode warn-don't-block +
  SAP stock reconcile (ADJUST-only), issues with §5.5a exposure (vendor double-entry
  RM−/AT_VENDOR+), credit/qty limit checks → waiver approvals (handlers registered),
  §11.12 corrections (reversal+reissue). 13 tests.
- P11-P13 (agent F): schedules (versioned, diff, §11.13 sanity + rollback-by-re-release),
  PROVISIONAL plan math (splits → line plans; BOM-explode → vendor call-offs) — parser/math
  marked provisional until the Bajaj sample lands. 8 tests.

## Wave 2
- P29-P31 (agent G): confirmations with §11.10 plan-revision pinning (mid-shift cuts can't
  block honest work — tested), reject-reason enforcement, BOM backflush stock, §11.11 PPC
  hold queue (nothing lost), auto shift close from calendar + posted_after_close flag,
  corrections via approvals. 8 tests. NOTE: per-line shift override (Domain_QA Q6) deferred —
  needs lines.shift_pattern column (migration packet).
- P34 (agent H): dispatches (FG stock policy-aware), SAP-invoice recording + qty-match
  (mismatch needs reason + soft anomaly), confirm-sale → live sales + INVOICE outbox. 7 tests.
- P32/P35 (agent I): achievement/yield/sales/overview dashboards, ETag/304, every KPI
  traceable, override-review KPI surfaced. 5 tests.

## Wave 3 (integrator)
- P40 outbox batcher + SFTP (atomic tmp→rename, seq files, checksum+trailer, MAX_ATTEMPTS,
  idle-without-config, recover_stuck) + CHAOS TESTS: crash mid-upload → zero loss zero dupes. 5 tests.
- worker.py: plain-loop scheduler (no Celery) running outbox/escalations/shift-close/
  blocker-repeat/digest jobs — every job an importable function.
- P41 reconciliation CSV exports from FROZEN outbox payloads + batch listing.
- P45 e2e thin slice: all 8 stages over HTTP, live plan↔confirmation join, outbox carrying
  all 5 record types, audit trail — passed first run. THE living spec, runs in CI.
- Wiring: 15 routers in main.py; plans views now join live confirmed totals.

## Remaining backend (blocked/deferred, in plan)
Bajaj schedule parser final form (sample pending) · SAP postback CSV spec + ack handling
(SAP team) · baseline Alembic migration + audit INSERT-only grant (dev machine, human
checkpoint) · weighbridge_weight + lines.shift_pattern columns (single migration packet) ·
vendor portal P37 (post-pilot per Domain_QA) · real SMS OTP · FCM push.

## Closeout addendum (items 8–10, 2026-06-12)
- goods_receipts += weighbridge_weight + weighbridge_slip_photo_id (schema+service+API);
  lines += shift_pattern JSON — auto-close now honors per-line shifts over the plant default
  (Domain_QA Q6/Q7 closed). Columns land in the baseline migration (not yet generated).
- escalations.resolve_events wired at all completion points: GR posted / PO linked /
  marked consumable (gate chains), approval decided/overridden (SLA chains), anomaly
  resolved (hard-block chain), agent heartbeat (stale chain).
- photos_pending_sweep job (24h, notify-once, idempotent) added to the worker.
- /healthz enriched: db + storage probe (S3 head_bucket / local write) + outbox backlog;
  degraded on any failed outbox row. Suite: 127/127 verify-lite green.
