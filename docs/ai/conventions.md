# Conventions (referenced from CLAUDE.md)

## Backend
- snake_case tables; doc_no prefixes: G- (gate), GR- (receipt), ISS- (issue), DN- (dispatch), RGP- (return pass).
- One router + model + service + schema + test file per domain, same stem (gate.py everywhere).
- Pydantic schemas mirror endpoints 1:1; response models always declared (OpenAPI is the contract).
- Statuses TEXT + CheckConstraint named ck_<table>_<name>; see models/base.py for type aliases.
- Factory fixtures in tests/factories.py; golden files under data/ are read-only.
- structlog JSON with request_id; never print().
- Service write path order (invariant 3): validate → anomaly rules → domain rows → stock_ledger → sap_outbox → soft anomalies/notifications → commit.

## Flutter (current state — see app/ARCHITECTURE.md + ADR-006 for the full rules)
- Five screen rules: S.t('en','मराठी') call-site strings (ARB later) · ApiException for all
  errors, switch on `code` never message text · transactional POSTs via retryQueueProvider
  with uuid client_ref (same ref on dialog-resubmits) · reads via Api.dio direct ·
  router.dart is the class-name contract.
- Shared widgets from widgets/common.dart only; new status colors go in theme.statusColors.
- Hand-written API calls mirror backend/docs/openapi.json 1:1 until openapi-generator
  runs on the dev machine (deviation, ADR-006).

## Docs (definition of done, every packet)
- docs/packets/P-XX.md updated: checklist + handoff note.
- Human-facing behaviour change → docs/human/ touched.
- New decision → docs/ai/decisions/ADR-NNN-*.md (one page max).
