"""Outbox batcher + SFTP sender (P40; ADR-002, Architecture §5.4).

State machine: outbox pending →(claim)→ batched →(verified upload)→ sent →(ack)→ acked,
or → failed after MAX_ATTEMPTS. Batches: building → uploaded → acked/failed.
Crash recovery (`recover_stuck`): 'building' batches put their rows back to pending —
at-least-once + SAP-side dedupe on record id; never at-most-once.
Without SFTP config the batcher stays idle (rows accumulate safely in pending).
"""
import csv
import hashlib
import io
import json

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.system import SapExportBatch, SapOutbox

MAX_ATTEMPTS = 5


def _csv_for(record_type: str, rows: list[SapOutbox]) -> bytes:
    """Deterministic CSV: union of payload keys, sorted; record_id always first.
    Trailer row carries the row count (SAP-side integrity check)."""
    keys = sorted({k for r in rows for k in (r.payload or {})})
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["record_id", "record_type", *keys])
    for r in rows:
        w.writerow([r.record_id, r.record_type,
                    *[json.dumps(r.payload.get(k)) if isinstance(r.payload.get(k), (dict, list))
                      else ("" if r.payload.get(k) is None else str(r.payload.get(k)))
                      for k in keys]])
    w.writerow([f"#TRAILER_ROWS={len(rows)}"])
    return buf.getvalue().encode()


class SftpTransport:
    """Thin paramiko wrapper. Tests inject a fake with the same .put_atomic API."""

    def __init__(self):
        s = get_settings()
        self.configured = bool(s.sap_sftp_host and s.sap_sftp_user)
        self._settings = s

    def put_atomic(self, filename: str, content: bytes) -> None:
        import paramiko  # lazy — not a sandbox dependency
        s = self._settings
        key = paramiko.RSAKey.from_private_key_file(s.sap_sftp_key_path)
        transport = paramiko.Transport((s.sap_sftp_host, 22))
        transport.connect(username=s.sap_sftp_user, pkey=key)
        try:
            sftp = paramiko.SFTPClient.from_transport(transport)
            tmp = f"{filename}.tmp"
            with sftp.open(tmp, "wb") as f:
                f.write(content)
            sftp.rename(tmp, filename)  # atomic publish — SAP never reads half a file
        finally:
            transport.close()


def recover_stuck(db: Session) -> int:
    """After a crash: 'building' batches never made it out — release their rows."""
    n = 0
    for batch in db.query(SapExportBatch).filter_by(status="building"):
        for row in db.query(SapOutbox).filter_by(batch_id=batch.id):
            row.status, row.batch_id = "pending", None
        batch.status = "failed"
        n += 1
    db.commit()
    return n


def process_outbox(db: Session, transport: SftpTransport | None = None) -> dict:
    """One batcher pass. Claims pending rows per record_type, builds + sends a batch.
    Returns counters for /healthz and logs."""
    transport = transport or SftpTransport()
    if not transport.configured:
        return {"idle": True, "pending": db.query(SapOutbox).filter_by(status="pending").count()}
    sent = failed = 0
    types = [t for (t,) in db.query(SapOutbox.record_type)
             .filter_by(status="pending").distinct()]
    for rt in types:
        rows = (db.query(SapOutbox).filter_by(status="pending", record_type=rt)
                .order_by(SapOutbox.id).limit(500).all())
        if not rows:
            continue
        seq = (db.query(SapExportBatch).count()) + 1
        content = _csv_for(rt, rows)
        batch = SapExportBatch(seq_no=seq, record_type=rt,
                               filename=f"{rt}_{seq:06d}.csv", row_count=len(rows),
                               checksum=hashlib.sha256(content).hexdigest(),
                               status="building")
        db.add(batch)
        db.flush()
        for r in rows:
            r.status, r.batch_id = "batched", batch.id
        db.commit()  # claim is durable before any network IO
        try:
            transport.put_atomic(batch.filename, content)
            batch.status = "uploaded"
            for r in rows:
                r.status = "sent"
            sent += len(rows)
        except Exception as exc:  # network/SFTP failure → rows go back, retry later
            batch.status = "failed"
            for r in rows:
                r.status = "pending" if r.attempts + 1 < MAX_ATTEMPTS else "failed"
                r.attempts += 1
                r.last_error = str(exc)[:500]
            failed += len(rows)
        db.commit()
    return {"idle": False, "sent": sent, "failed": failed}


def backlog(db: Session) -> dict:
    out = {}
    for status in ("pending", "batched", "failed"):
        out[status] = db.query(SapOutbox).filter_by(status=status).count()
    return out
