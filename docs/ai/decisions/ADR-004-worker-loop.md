# ADR-004: Plain interval-loop worker, not APScheduler/Celery
Date: 2026-06-12 · Status: accepted (supersedes the APScheduler mention in early drafts)
Decision: app/worker.py is a while-loop with per-job intervals; every job is an importable
pure-ish function (process_outbox, escalation_scan, shift_auto_close_job, blocker_repeat,
digest_bundle, photos_pending_sweep) tested directly with fake clocks.
Why: zero extra deps, trivially debuggable (run any job once via run_once()), jobs are
idempotent so crash-restart is the whole recovery story. Escape hatch: swap the loop for
APScheduler later without touching any job.
