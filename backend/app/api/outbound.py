"""Outbound (dispatch + sales invoice + confirm) router (P34). HTTP concerns ONLY —
all business logic lives in services/outbound.py (CLAUDE.md).
NOTE: register in app/main.py with `app.include_router(outbound_router)` —
wiring main.py is outside this packet's file list (tests mount it themselves).
ROLE NOTE: there is no 'commercial' role in §4.1 — invoice record/confirm are
guarded plant_ops/admin until such a role exists (documented packet decision)."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.models.outbound import Dispatch, SalesInvoice
from app.models.workflow import Anomaly
from app.schemas import outbound as s
from app.services import outbound as svc
from app.services.master import get_or_404

router = APIRouter(prefix="/api/v1", tags=["outbound"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
read_guard = require(*INTERNAL)
write_guard = require("plant_ops", "admin")


def _dispatch_read(db: Session, d: Dispatch) -> s.DispatchRead:
    out = s.DispatchRead.model_validate(d)
    out.lines = [s.DispatchLineRead.model_validate(ln)
                 for ln in svc.dispatch_lines(db, d.id)]
    # §11.1 warn flag survives idempotent replay: derived from the soft anomaly rows.
    out.stock_warning = bool(
        db.query(Anomaly.id)
        .filter_by(ref_type="dispatches", ref_id=d.id,
                   rule_code="stock_insufficient_warned").first())
    return out


def _invoice_read(db: Session, inv: SalesInvoice) -> s.InvoiceRead:
    out = s.InvoiceRead.model_validate(inv)
    out.lines = [s.InvoiceLineRead.model_validate(ln)
                 for ln in svc.invoice_lines(db, inv.id)]
    return out


# --- dispatches ---
@router.post("/dispatches", response_model=s.DispatchRead)
def create_dispatch(body: s.DispatchCreate, db: Session = Depends(get_db),
                    user: CurrentUser = Depends(write_guard)):
    """200 (not 201): a retried client_ref returns the ORIGINAL result (invariant 4)."""
    return _dispatch_read(db, svc.create_dispatch(db, user, body))


@router.get("/dispatches", response_model=list[s.DispatchRead])
def list_dispatches(status: str | None = Query(None),
                    limit: int = 200, offset: int = 0,
                    db: Session = Depends(get_db),
                    _: CurrentUser = Depends(read_guard)):
    q = db.query(Dispatch)
    if status:
        q = q.filter_by(status=status)
    rows = q.order_by(Dispatch.id.desc()).limit(limit).offset(offset).all()
    return [_dispatch_read(db, r) for r in rows]


@router.get("/dispatches/{dispatch_id}", response_model=s.DispatchRead)
def get_dispatch(dispatch_id: int, db: Session = Depends(get_db),
                 _: CurrentUser = Depends(read_guard)):
    return _dispatch_read(db, get_or_404(db, Dispatch, dispatch_id, "dispatch"))


# --- sales invoices (SAP-created; app records + confirms — Domain_QA Q2) ---
@router.post("/invoices", response_model=s.InvoiceRead)
def record_invoice(body: s.InvoiceCreate, db: Session = Depends(get_db),
                   user: CurrentUser = Depends(write_guard)):
    return _invoice_read(db, svc.record_invoice(db, user, body))


@router.post("/invoices/{invoice_id}/confirm", response_model=s.InvoiceRead)
def confirm_sale(invoice_id: int, db: Session = Depends(get_db),
                 user: CurrentUser = Depends(write_guard)):
    return _invoice_read(db, svc.confirm_sale(db, user, invoice_id))


@router.get("/invoices", response_model=list[s.InvoiceRead])
def list_invoices(status: str | None = Query(None),
                  dispatch_id: int | None = Query(None),
                  limit: int = 200, offset: int = 0,
                  db: Session = Depends(get_db),
                  _: CurrentUser = Depends(read_guard)):
    q = db.query(SalesInvoice)
    if status:
        q = q.filter_by(status=status)
    if dispatch_id:
        q = q.filter_by(dispatch_id=dispatch_id)
    rows = q.order_by(SalesInvoice.id.desc()).limit(limit).offset(offset).all()
    return [_invoice_read(db, r) for r in rows]


@router.get("/invoices/{invoice_id}", response_model=s.InvoiceRead)
def get_invoice(invoice_id: int, db: Session = Depends(get_db),
                _: CurrentUser = Depends(read_guard)):
    return _invoice_read(db, get_or_404(db, SalesInvoice, invoice_id, "invoice"))
