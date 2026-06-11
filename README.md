# Yeshshree Operations App

Operations layer over SAP for Yeshshree Press Comps, plant 1117 (Tier-1 to Bajaj Auto).
8-stage flow: Bajaj schedule → plan cascade → gate/QC/GR → issue → production confirmation →
dispatch → billing → live dashboards. Pilot: parallel run with SAP + paper.

**Start here:** `CLAUDE.md` (agents) · `docs/human/` (how it works, admin guide, runbook)
· `docs/planning/` (plan, architecture, premortem, playbook) · `docs/packets/` (work-packet log).

| Part | Status (2026-06-12) |
|---|---|
| backend/ (FastAPI + Postgres) | **Functionally complete**: 127 tests, ~90 endpoints, all 8 stages e2e-tested. Pending: baseline migration (dev machine), Bajaj schedule format, SAP CSV/ack spec. |
| gate-agent/ (ScanJet watcher) | Built (agent.py + heartbeat); .exe packaging on Windows pending |
| app/ (Flutter Android+Web) | not started (P09) |

## Quick start (dev machine)
    cp .env.example .env
    docker-compose up -d
    make migration m="baseline"     # generate + review the first migration (HUMAN checkpoint)
    docker-compose run --rm api alembic upgrade head
    make verify                     # full gate

In the Cowork sandbox (no docker/flutter): `make verify-lite`.
