# Conventions (referenced from CLAUDE.md)

## Backend
- snake_case tables; doc_no prefixes: G- (gate), GR- (receipt), ISS- (issue), DN- (dispatch), RGP- (return pass).
- One router + model + service + schema + test file per domain, same stem (gate.py everywhere).
- Pydantic schemas mirror endpoints 1:1; response models always declared (OpenAPI is the contract).
- Statuses TEXT + CheckConstraint named ck_<table>_<name>; see models/base.py for type aliases.
- Factory fixtures in tests/factories.py; golden files under data/ are read-only.
- structlog JSON with request_id; never print().
- Service write path order (invariant 3): validate → anomaly rules → domain rows → stock_ledger → sap_outbox → soft anomalies/notifications → commit.

## Flutter
- Generated Dio client only (make openapi → generator). Never hand-written HTTP.
- Every user-facing string is an ARB key, en + mr.
- UI switches on error envelope `code`, never message text.

## Docs (definition of done, every packet)
- docs/packets/P-XX.md updated: checklist + handoff note.
- Human-facing behaviour change → docs/human/ touched.
- New decision → docs/ai/decisions/ADR-NNN-*.md (one page max).
