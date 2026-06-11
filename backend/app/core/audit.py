"""Audit (CLAUDE.md invariant 1). Two layers:

1. HTTP middleware — EVERY mutating request writes one audit_log row (who/where/what
   endpoint). Request bodies are NEVER stored here (passwords, PINs).
2. `record()` helper — services call it for field-level before/after on the entity
   they changed (SAP CDHDR/CDPOS equivalent), inside the SAME domain transaction.

audit_log is INSERT-only; on Postgres the app role has no UPDATE/DELETE grant
(baseline migration); SQLite tests enforce by convention + test_audit.py.
"""
from sqlalchemy.orm import Session

from app.models.system import AuditLog

_MUTATING = {"POST", "PUT", "PATCH", "DELETE"}
_ACTION_BY_METHOD = {"POST": "create", "PUT": "update", "PATCH": "update", "DELETE": "update"}


def _entity_from_path(path: str) -> str:
    parts = [p for p in path.split("/") if p and p not in ("api", "v1")]
    return parts[0] if parts else "unknown"


def action_for(method: str, path: str) -> str:
    if "/auth/" in path:
        return "login"
    if "/exports" in path:
        return "export"
    return _ACTION_BY_METHOD.get(method, "update")


def write_request_audit(db: Session, *, request, response_status: int) -> None:
    user = getattr(request.state, "user", None)
    db.add(AuditLog(
        request_id=getattr(request.state, "request_id", None),
        user_id=user.id if user else None,
        role=user.role if user else None,
        station=user.station if user else None,
        device_key=user.device_key if user else None,
        method=request.method,
        path=str(request.url.path),
        entity=_entity_from_path(request.url.path),
        entity_id=None,
        action=action_for(request.method, request.url.path),
        before=None,
        after={"status": response_status},
    ))


def is_mutating(method: str) -> bool:
    return method in _MUTATING


def record(db: Session, *, user_id: int | None, entity: str, entity_id: int,
           action: str, before: dict | None, after: dict | None,
           request_id: str | None = None) -> None:
    """Field-level change document — call from services inside the domain transaction."""
    db.add(AuditLog(request_id=request_id, user_id=user_id, role=None, station=None,
                    device_key=None, method=None, path=None, entity=entity,
                    entity_id=entity_id, action=action, before=before, after=after))
