# ADR-003: Parallel-run pilot, warn-don't-block stock policy
Date: 2026-06-10 · Status: accepted
Decision: SAP + paper continue during pilot. ops_mode=parallel_run: stock checks warn, never block; SAP stock snapshot import reconciles via ADJUST ledger rows. Switch to authoritative is a business decision (human checkpoint).
Why: physical stock WILL diverge from app stock in week one; blocking legit issues kills user trust (Failure Scenarios #15). A truck never waits on the app.
