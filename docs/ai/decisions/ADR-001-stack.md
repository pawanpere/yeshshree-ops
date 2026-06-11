# ADR-001: FastAPI + PostgreSQL monolith, Flutter single codebase
Date: 2026-06-10 · Status: accepted
Decision: modular monolith (FastAPI + SQLAlchemy + Alembic + Postgres 16), Flutter for Android+Web, no microservices/queues/k8s.
Why: AI-maintainability is the top criterion — one greppable codebase, best training coverage, OpenAPI-generated client, docker repro. Load (≤100 concurrent) is trivial for one API + one PG.
Alternatives rejected: Supabase (logic split across SQL policies/edge functions/dashboard), Firebase (NoSQL vs heavily relational domain), NestJS (fine, but Python parsers for SAP files tip it).
