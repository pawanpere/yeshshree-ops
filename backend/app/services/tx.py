"""The uniform write path (P08; CLAUDE.md invariants 3 & 4).

Every transactional service uses these two primitives:

    existing = idempotent_replay(db, GateEntry, client_ref)
    if existing:
        return existing                      # retried request → original result, 200
    ... validate, write domain rows ...
    enqueue_outbox(db, "GR", gr.id, payload) # SAME transaction as the domain rows
    db.commit()                              # everything or nothing

`enqueue_outbox` must be called BEFORE the commit that persists the domain row —
there is no state where a row exists without its outbox entry (ADR-002).
"""
import uuid

from sqlalchemy.orm import Session

from app.models.system import SapOutbox

OUTBOX_RECORD_TYPES = {"GR", "CONFIRMATION", "ISSUE", "DISPATCH", "INVOICE"}


def idempotent_replay(db: Session, model, client_ref: uuid.UUID | str):
    """Return the existing row for this client_ref, or None. Callers return the
    existing row as a normal 200 — the client's retry queue can fire blindly."""
    if isinstance(client_ref, str):
        client_ref = uuid.UUID(client_ref)
    return db.query(model).filter_by(client_ref=client_ref).one_or_none()


def enqueue_outbox(db: Session, record_type: str, record_id: int, payload: dict) -> SapOutbox:
    """Add the SAP postback row to the CURRENT (uncommitted) transaction.
    Payload is frozen here — later master-data edits never change what we told SAP."""
    if record_type not in OUTBOX_RECORD_TYPES:
        raise ValueError(f"Unknown outbox record_type {record_type!r}")
    row = SapOutbox(record_type=record_type, record_id=record_id,
                    payload=payload, status="pending", attempts=0)
    db.add(row)
    return row
