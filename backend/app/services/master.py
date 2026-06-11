"""Master-data CRUD logic (P10). Rules (CLAUDE.md never-do + §11.15):
- NO deletes, ever — deactivate via is_active=false.
- Admin/planning-created rows get source='manual' (importers reconcile on next SAP file).
- Every change writes a field-level audit diff in the same transaction.
- sap_code / sap_order_no are immutable after create (SAP owns them).
"""
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error


def apply_update(db: Session, obj, changes: dict, user: CurrentUser, entity: str,
                 allowed: set[str]) -> dict:
    """Diff-apply `changes` restricted to `allowed` fields; audit before/after; commit."""
    illegal = set(changes) - allowed
    if illegal:
        raise _error("FIELD_NOT_EDITABLE", f"Cannot edit: {', '.join(sorted(illegal))}",
                     "हे फील्ड बदलता येत नाही", 422, {"fields": sorted(illegal)})
    before, after = {}, {}
    for field, new in changes.items():
        old = getattr(obj, field)
        if old != new:
            before[field] = str(old) if old is not None else None
            after[field] = str(new) if new is not None else None
            setattr(obj, field, new)
    if after:
        record(db, user_id=user.id, entity=entity, entity_id=obj.id,
               action="update", before=before, after=after)
        db.commit()
    return after


def create_with_audit(db: Session, obj, user: CurrentUser, entity: str):
    db.add(obj)
    db.flush()
    record(db, user_id=user.id, entity=entity, entity_id=obj.id, action="create",
           before=None, after={"created": True})
    db.commit()
    db.refresh(obj)
    return obj


def get_or_404(db: Session, model, obj_id: int, entity: str):
    obj = db.get(model, obj_id)
    if obj is None:
        raise _error("NOT_FOUND", f"{entity} not found", "सापडले नाही", 404,
                     {"entity": entity, "id": obj_id})
    return obj
