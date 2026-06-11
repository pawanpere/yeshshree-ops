# Yeshshree Operations App

Operations layer over SAP for Yeshshree Press Comps, plant 1117 (Tier-1 to Bajaj Auto).
8-stage flow: Bajaj schedule → plan cascade → gate/QC/GR → issue → production confirmation →
dispatch → billing → live dashboards. Pilot: parallel run with SAP + paper.

**Start here:** `CLAUDE.md` (agents) · `docs/planning/` (plan, architecture, premortem, playbook)
· `docs/packets/` (work-packet log).

| Part | Status |
|---|---|
| backend/ (FastAPI + Postgres) | P01–P03 done: scaffold, CI, full 53-table schema |
| app/ (Flutter Android+Web) | not started (P09) |
| gate-agent/ (ScanJet watcher) | not started (P19) |

## Quick start (dev machine)
    cp .env.example .env
    docker-compose up -d
    make migration m="baseline"     # generate + review the first migration (HUMAN checkpoint)
    docker-compose run --rm api alembic upgrade head
    make verify                     # full gate

In the Cowork sandbox (no docker/flutter): `make verify-lite`.
