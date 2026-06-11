"""Approvals + delegations router (P25/P26). HTTP concerns ONLY — engine lives in
services/approvals.py (CLAUDE.md). NOTE: register in app/main.py with
`app.include_router(approvals_router)` — wiring main.py is outside this packet's
file list (tests mount it themselves).
Deactivation is PATCH {is_active:false} — there is NO http DELETE (never-do)."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, _error, require
from app.models.workflow import Approval
from app.schemas import workflow as s
from app.services import approvals as svc

router = APIRouter(prefix="/api/v1/approvals", tags=["approvals"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
internal_guard = require(*INTERNAL)


@router.get("/inbox", response_model=list[s.ApprovalRead])
def approvals_inbox(db: Session = Depends(get_db),
                    user: CurrentUser = Depends(internal_guard)):
    """Open approvals the caller can act on — own role or active delegation."""
    return svc.inbox(db, user)


# --- delegations (§11.2) — literal paths BEFORE /{approval_id} routes ---
@router.post("/delegations", response_model=s.DelegationRead, status_code=201)
def create_delegation(body: s.DelegationCreate, db: Session = Depends(get_db),
                      user: CurrentUser = Depends(internal_guard)):
    return svc.create_delegation(db, user, principal_user_id=body.principal_user_id,
                                 delegate_user_id=body.delegate_user_id,
                                 approval_type=body.approval_type,
                                 valid_from=body.valid_from, valid_to=body.valid_to)


@router.get("/delegations", response_model=list[s.DelegationRead])
def list_delegations(db: Session = Depends(get_db),
                     user: CurrentUser = Depends(internal_guard)):
    return svc.list_delegations(db, user)


@router.patch("/delegations/{delegation_id}", response_model=s.DelegationRead)
def deactivate_delegation(delegation_id: int, body: s.DelegationUpdate,
                          db: Session = Depends(get_db),
                          user: CurrentUser = Depends(internal_guard)):
    """DELETE-as-deactivate: only {is_active: false} is accepted (never-do: no DELETE)."""
    if body.is_active is not False:
        raise _error("DELEGATION_ONLY_DEACTIVATE",
                     "Delegations can only be deactivated — create a new one instead",
                     "प्रतिनिधित्व फक्त निष्क्रिय करता येते — नवे तयार करा", 422, {})
    return svc.deactivate_delegation(db, user, delegation_id)


# --- approvals ---
@router.get("", response_model=list[s.ApprovalRead])
def list_approvals(status: str | None = Query(None),
                   limit: int = 200, offset: int = 0,
                   db: Session = Depends(get_db),
                   _: CurrentUser = Depends(internal_guard)):
    q = db.query(Approval)
    if status:
        q = q.filter_by(status=status)
    return q.order_by(Approval.id.desc()).limit(limit).offset(offset).all()


@router.post("/{approval_id}/decide", response_model=s.ApprovalRead)
def decide(approval_id: int, body: s.DecideRequest, db: Session = Depends(get_db),
           user: CurrentUser = Depends(internal_guard)):
    return svc.decide(db, user, approval_id, body.decision, body.note)


@router.post("/{approval_id}/override", response_model=s.ApprovalRead)
def override(approval_id: int, body: s.OverrideRequest, db: Session = Depends(get_db),
             user: CurrentUser = Depends(require("management", "admin"))):
    """§11.2 emergency override — post-facto override_review is auto-created."""
    return svc.override(db, user, approval_id, body.reason)
