"""Receiving (GR/QC) + anomaly-register router (P20/P21). HTTP concerns ONLY —
all GR/anomaly business logic lives in services/receiving.py (CLAUDE.md).
NOTE: register in app/main.py with `app.include_router(receiving_router)` —
wiring main.py is outside this packet's file list (tests mount it themselves)."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.models.inventory import GoodsReceipt
from app.models.workflow import Anomaly
from app.schemas import receiving as s
from app.services import receiving as svc
from app.services.master import get_or_404

router = APIRouter(prefix="/api/v1", tags=["receiving"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
read_guard = require(*INTERNAL)


# --- goods receipts ---
@router.post("/goods-receipts", response_model=s.GoodsReceiptRead)
def post_goods_receipt(body: s.GoodsReceiptCreate, db: Session = Depends(get_db),
                       user: CurrentUser = Depends(require("plant_ops", "admin"))):
    """200 (not 201): a retried client_ref returns the ORIGINAL result (invariant 4)."""
    return svc.post_goods_receipt(db, user, body)


@router.get("/goods-receipts", response_model=list[s.GoodsReceiptRead])
def list_goods_receipts(gate_entry_id: int | None = None,
                        limit: int = 200, offset: int = 0,
                        db: Session = Depends(get_db),
                        _: CurrentUser = Depends(read_guard)):
    q = db.query(GoodsReceipt)
    if gate_entry_id:
        q = q.filter_by(gate_entry_id=gate_entry_id)
    return q.order_by(GoodsReceipt.id.desc()).limit(limit).offset(offset).all()


@router.get("/goods-receipts/{gr_id}", response_model=s.GoodsReceiptRead)
def get_goods_receipt(gr_id: int, db: Session = Depends(get_db),
                      _: CurrentUser = Depends(read_guard)):
    return get_or_404(db, GoodsReceipt, gr_id, "goods receipt")


# --- anomaly register (P21) ---
@router.get("/anomalies", response_model=list[s.AnomalyRead])
def list_anomalies(status: str | None = Query(None), severity: str | None = Query(None),
                   limit: int = 200, offset: int = 0,
                   db: Session = Depends(get_db),
                   _: CurrentUser = Depends(read_guard)):
    q = db.query(Anomaly)
    if status:
        q = q.filter_by(status=status)
    if severity:
        q = q.filter_by(severity=severity)
    return q.order_by(Anomaly.id.desc()).limit(limit).offset(offset).all()


@router.post("/anomalies/{anomaly_id}/resolve", response_model=s.AnomalyRead)
def resolve_anomaly(anomaly_id: int, body: s.AnomalyResolve,
                    db: Session = Depends(get_db),
                    user: CurrentUser = Depends(
                        require("plant_ops", "supervisor", "management", "admin"))):
    return svc.resolve_anomaly(db, user, anomaly_id, body.note)
