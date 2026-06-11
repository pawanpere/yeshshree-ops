"""Production confirmations + holds + corrections router (P29/P30/P31). HTTP concerns
ONLY — all business logic lives in services/production.py (CLAUDE.md).
NOTE: register in app/main.py with `app.include_router(production_router)` —
wiring main.py is outside this packet's file list (tests mount it themselves)."""
import datetime as dt

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.models.production import ConfirmationHold
from app.schemas import production as s
from app.services import production as svc

router = APIRouter(prefix="/api/v1", tags=["production"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
read_guard = require(*INTERNAL)


def _conf_read(conf, sap_status: str | None = None) -> s.ConfirmationRead:
    out = s.ConfirmationRead.model_validate(conf)
    out.sap_sync_status = sap_status
    return out


@router.post("/confirmations", response_model=s.ConfirmationRead)
def post_confirmation(body: s.ConfirmationCreate, db: Session = Depends(get_db),
                      user: CurrentUser = Depends(require("supervisor", "admin"))):
    """200 (not 201): a retried client_ref returns the ORIGINAL result (invariant 4)."""
    return _conf_read(svc.post_confirmation(db, user, body), "pending")


@router.post("/confirmations/hold", response_model=s.HoldRead)
def hold_confirmation(body: s.ConfirmationCreate, db: Session = Depends(get_db),
                      user: CurrentUser = Depends(require("supervisor", "admin"))):
    """§11.11 — no resolvable order: store the full body, nothing lost, nothing posted."""
    return svc.hold_confirmation(db, user, body)


@router.get("/confirmations", response_model=list[s.ConfirmationRead])
def list_confirmations(line_id: int | None = Query(None),
                       date: dt.date | None = Query(None),
                       limit: int = 200, offset: int = 0,
                       db: Session = Depends(get_db),
                       _: CurrentUser = Depends(read_guard)):
    """History incl. SAP outbox status (pending/batched/sent/… as sap_sync_status)."""
    rows = svc.history(db, line_id=line_id, on_date=date, limit=limit, offset=offset)
    return [_conf_read(conf, sap_status) for conf, sap_status in rows]


@router.post("/confirmations/{confirmation_id}/correction",
             response_model=s.CorrectionRead)
def request_correction(confirmation_id: int, body: s.CorrectionCreate,
                       db: Session = Depends(get_db),
                       user: CurrentUser = Depends(require("supervisor", "admin"))):
    return svc.request_correction(db, user, confirmation_id,
                                  body.delta_good, body.delta_reject, body.reason)


@router.get("/confirmations/holds", response_model=list[s.HoldRead])
def list_holds(status: str | None = Query("open"), limit: int = 200, offset: int = 0,
               db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    q = db.query(ConfirmationHold)
    if status:
        q = q.filter_by(status=status)
    return q.order_by(ConfirmationHold.id.desc()).limit(limit).offset(offset).all()


@router.post("/confirmations/holds/{hold_id}/resolve",
             response_model=s.HoldResolveResult)
def resolve_hold(hold_id: int, body: s.HoldResolve, db: Session = Depends(get_db),
                 user: CurrentUser = Depends(require("planning", "admin"))):
    hold, conf = svc.resolve_hold(db, user, hold_id, body)
    return s.HoldResolveResult(hold=s.HoldRead.model_validate(hold),
                               confirmation=_conf_read(conf, "pending"))
