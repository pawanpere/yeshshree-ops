"""Background worker — `python -m app.worker`. Deliberately a plain loop, not Celery
(ADR-001 boring-tech): every job is an importable, testable function; the worker only
schedules them. Jobs are idempotent — a crashed worker just restarts.
"""
import time
import traceback

import structlog
from sqlalchemy.orm import Session

from app.core.db import get_engine
from app.sap_sync.batcher import process_outbox, recover_stuck
from app.services.escalations import escalation_scan
from app.services.notifications import blocker_repeat, digest_bundle
from app.services.production import shift_auto_close_job
from app.services.sweeps import photos_pending_sweep

log = structlog.get_logger()

JOBS = [  # (name, fn(db), interval_seconds)
    ("outbox", lambda db: process_outbox(db), 300),
    ("escalations", lambda db: escalation_scan(db), 300),
    ("shift_auto_close", lambda db: shift_auto_close_job(db), 300),
    ("blocker_repeat", lambda db: blocker_repeat(db), 900),
    ("digest_bundle", lambda db: digest_bundle(db), 3600),
    ("photos_pending_sweep", lambda db: photos_pending_sweep(db), 86400),
]


def run_once(names: list[str] | None = None) -> dict:
    """Run each (selected) job exactly once — used by tests and `--once`."""
    results = {}
    engine = get_engine()
    for name, fn, _ in JOBS:
        if names and name not in names:
            continue
        with Session(engine) as db:
            try:
                results[name] = fn(db)
            except Exception:
                log.error("job_failed", job=name, exc=traceback.format_exc())
                results[name] = "error"
    return results


def main() -> None:
    log.info("worker_start")
    with Session(get_engine()) as db:
        recovered = recover_stuck(db)
        if recovered:
            log.warning("recovered_stuck_batches", count=recovered)
    last_run = {name: 0.0 for name, _, _ in JOBS}
    while True:
        now = time.monotonic()
        for name, fn, interval in JOBS:
            if now - last_run[name] >= interval:
                last_run[name] = now
                with Session(get_engine()) as db:
                    try:
                        out = fn(db)
                        log.info("job_done", job=name, result=str(out)[:200])
                    except Exception:
                        log.error("job_failed", job=name, exc=traceback.format_exc())
        time.sleep(5)


if __name__ == "__main__":
    main()
