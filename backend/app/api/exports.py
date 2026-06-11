"""Reconciliation exports (P41) — the parallel-run safety net (ADR-003): one CSV per
transaction type per day, compared against SAP's own reports until trust is earned."""
import csv
import io
from datetime import date

from fastapi import APIRouter, Depends
from fastapi.responses import PlainTextResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, _error, require
from app.models.system import SapExportBatch, SapOutbox

router = APIRouter(prefix="/api/v1/exports", tags=["exports"])

guard = require("admin", "management", "planning")

TYPES = ("GR", "CONFIRMATION", "ISSUE", "DISPATCH", "INVOICE")


@router.get("/reconciliation", response_class=PlainTextResponse)
def reconciliation(on_date: date, record_type: str,
                   db: Session = Depends(get_db), _: CurrentUser = Depends(guard)) -> str:
    """CSV of everything the app captured for that day, from the FROZEN outbox payloads
    (exactly what SAP was/will be told — not today's mutable state)."""
    if record_type not in TYPES:
        raise _error("EXPORT_TYPE_UNKNOWN", f"type must be one of {TYPES}",
                     "अज्ञात प्रकार", 422)
    rows = (db.query(SapOutbox)
            .filter(SapOutbox.record_type == record_type)
            .filter(func.date(SapOutbox.created_at) == on_date)
            .order_by(SapOutbox.id).all())
    keys = sorted({k for r in rows for k in (r.payload or {})})
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["record_id", "outbox_status", *keys])
    for r in rows:
        w.writerow([r.record_id, r.status,
                    *[str(r.payload.get(k, "")) for k in keys]])
    return buf.getvalue()


@router.get("/sap-batches")
def sap_batches(db: Session = Depends(get_db), _: CurrentUser = Depends(guard)):
    out = []
    for b in db.query(SapExportBatch).order_by(SapExportBatch.seq_no.desc()).limit(100):
        out.append({"seq_no": b.seq_no, "record_type": b.record_type,
                    "filename": b.filename, "row_count": b.row_count,
                    "checksum": b.checksum, "status": b.status})
    return out
