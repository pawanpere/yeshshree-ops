"""P40 acceptance: batcher state machine, chaos (crash mid-upload → zero loss, zero
dupes), idle-without-config, recovery."""
import uuid

import pytest

from app.core.security import hash_password
from app.models.gate import GateEntry
from app.models.identity import User
from app.models.system import SapExportBatch, SapOutbox
from app.sap_sync.batcher import process_outbox, recover_stuck
from app.services.tx import enqueue_outbox


class FakeSFTP:
    def __init__(self, fail_on: set[str] | None = None):
        self.configured = True
        self.uploaded: dict[str, bytes] = {}
        self.fail_on = fail_on or set()

    def put_atomic(self, filename: str, content: bytes) -> None:
        if filename in self.fail_on or "*" in self.fail_on:
            raise ConnectionError("simulated network failure")
        self.uploaded[filename] = content


@pytest.fixture()
def seeded(db):
    u = User(username="g", password_hash=hash_password("x"), full_name="G",
             role="plant_ops", station="gate", language="en")
    db.add(u)
    db.commit()
    for i in range(3):
        ref = uuid.uuid4()
        e = GateEntry(doc_no=f"G-{i:05d}", vehicle_no="MH12", driver_name="D",
                      match_status="unmatched", status="open", client_ref=ref,
                      created_by=u.id)
        db.add(e)
        db.flush()
        enqueue_outbox(db, "GR", e.id, {"doc_no": e.doc_no, "qty": str(100 + i)})
    db.commit()
    return db


def test_happy_batch_and_send(seeded):
    db = seeded
    fake = FakeSFTP()
    out = process_outbox(db, transport=fake)
    assert out["sent"] == 3 and out["failed"] == 0
    assert db.query(SapOutbox).filter_by(status="sent").count() == 3
    batch = db.query(SapExportBatch).one()
    assert batch.status == "uploaded" and batch.row_count == 3
    content = fake.uploaded[batch.filename].decode()
    assert "#TRAILER_ROWS=3" in content and "record_id" in content


def test_crash_mid_upload_no_loss_no_dupes(seeded):
    db = seeded
    # First pass: upload fails → rows back to pending with attempts+1
    out1 = process_outbox(db, transport=FakeSFTP(fail_on={"*"}))
    assert out1["failed"] == 3
    assert db.query(SapOutbox).filter_by(status="pending").count() == 3
    assert db.query(SapExportBatch).filter_by(status="failed").count() == 1
    # Second pass: succeeds — each record sent EXACTLY once
    fake = FakeSFTP()
    out2 = process_outbox(db, transport=fake)
    assert out2["sent"] == 3
    sent_ids = [r.record_id for r in db.query(SapOutbox).filter_by(status="sent")]
    assert len(sent_ids) == len(set(sent_ids)) == 3
    assert len(fake.uploaded) == 1  # one successful file


def test_idle_without_sftp_config(seeded):
    class Unconfigured:
        configured = False
    out = process_outbox(seeded, transport=Unconfigured())
    assert out["idle"] is True and out["pending"] == 3
    assert seeded.query(SapExportBatch).count() == 0  # nothing claimed while idle


def test_recover_stuck_building_batches(seeded):
    db = seeded
    # Simulate a crash AFTER claim, BEFORE upload: rows batched, batch building
    rows = db.query(SapOutbox).all()
    batch = SapExportBatch(seq_no=99, record_type="GR", filename="GR_000099.csv",
                           row_count=3, checksum="x", status="building")
    db.add(batch)
    db.flush()
    for r in rows:
        r.status, r.batch_id = "batched", batch.id
    db.commit()
    n = recover_stuck(db)
    assert n == 1
    assert db.query(SapOutbox).filter_by(status="pending").count() == 3


def test_exhausted_attempts_marks_failed(seeded):
    db = seeded
    for r in db.query(SapOutbox).all():
        r.attempts = 4  # one more failure crosses MAX_ATTEMPTS=5
    db.commit()
    process_outbox(db, transport=FakeSFTP(fail_on={"*"}))
    assert db.query(SapOutbox).filter_by(status="failed").count() == 3
