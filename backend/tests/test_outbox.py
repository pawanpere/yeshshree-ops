"""P08 acceptance: outbox atomicity + client_ref idempotency (invariants 3 & 4)."""
import uuid

import pytest
from sqlalchemy.exc import IntegrityError

from app.core.security import hash_password
from app.models.gate import GateEntry
from app.models.identity import User
from app.models.system import SapOutbox
from app.services.tx import enqueue_outbox, idempotent_replay


@pytest.fixture()
def guard_id(db) -> int:
    u = User(username="gate1", password_hash=hash_password("x"), full_name="G",
             role="plant_ops", station="gate", language="mr")
    db.add(u)
    db.commit()
    return u.id


def _gate_entry(ref: uuid.UUID, created_by: int) -> GateEntry:
    return GateEntry(doc_no=f"G-{ref.hex[:6]}", vehicle_no="MH12MV9997",
                     driver_name="R. Singh", match_status="unmatched", status="open",
                     client_ref=ref, created_by=created_by)


def test_domain_row_and_outbox_commit_together(db, guard_id):
    ref = uuid.uuid4()
    entry = _gate_entry(ref, guard_id)
    db.add(entry)
    db.flush()
    enqueue_outbox(db, "GR", entry.id, {"doc_no": entry.doc_no, "qty": "100"})
    db.commit()
    assert db.query(SapOutbox).filter_by(record_type="GR", record_id=entry.id,
                                         status="pending").count() == 1


def test_rollback_removes_both(db, guard_id):
    """Crash between domain write and commit → NEITHER row exists (invariant 3)."""
    ref = uuid.uuid4()
    entry = _gate_entry(ref, guard_id)
    db.add(entry)
    db.flush()
    enqueue_outbox(db, "GR", entry.id, {"doc_no": entry.doc_no})
    db.rollback()  # simulated crash
    assert db.query(GateEntry).count() == 0
    assert db.query(SapOutbox).count() == 0


def test_client_ref_replay_returns_original(db, guard_id):
    ref = uuid.uuid4()
    db.add(_gate_entry(ref, guard_id))
    db.commit()
    original = idempotent_replay(db, GateEntry, ref)
    assert original is not None and original.client_ref == ref
    # and the DB-level guarantee behind it: duplicate insert is impossible
    db.add(_gate_entry(ref, guard_id))
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()
    assert idempotent_replay(db, GateEntry, str(ref)) is not None  # str form accepted


def test_unknown_record_type_rejected(db):
    with pytest.raises(ValueError):
        enqueue_outbox(db, "NOT_A_TYPE", 1, {})
