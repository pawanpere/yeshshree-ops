# Human docs — Yeshshree Operations App

Plain-English documentation for the people who run the system. Written for Kartik
(developer/admin) and Yeshshree plant staff (planning head, store/QC leads).

| Doc | What it covers |
|---|---|
| [how-the-system-works.md](how-the-system-works.md) | The 8-stage flow from schedule to billing — what each user does, what the system does behind it, what can block them, and who unblocks. |
| [admin-guide.md](admin-guide.md) | Day-to-day admin: users, devices, config tables, pilot data, anomaly register, master-data hygiene, SAP stock snapshot. |
| [runbook.md](runbook.md) | Operations: local dev, env vars, the background worker, gate-agent install, SFTP recovery, health checks, backups, known limits. |

Deeper material lives elsewhere:

- `docs/planning/` — the MVP plan, backend architecture, Domain Q&A, failure scenarios.
- `docs/packets/` — the work-packet log: what was actually built, and the decisions made.
- `CLAUDE.md` (repo root) — commands, invariants, and conventions for AI agents.

These docs describe what exists today. Anything still pending is marked as pending —
see the "Known limits" section of the runbook for the honest list.
