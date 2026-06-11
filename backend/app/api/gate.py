"""Gate entries router (P16+P18). HTTP concerns ONLY — all logic in services/gate.py.
Writes: gate operators (plant_ops) + admin. Reads: any internal role; vendors 403.
POST routes return 200 even on idempotent replay (CLAUDE.md invariant 4)."""
import datetime as dt

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.schemas import gate as s
from app.services import gate as svc

router = APIRouter(prefix="/api/v1/gate-entries", tags=["gate"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
WRITERS = ("plant_ops", "admin")

read_guard = require(*INTERNAL)
write_guard = require(*WRITERS)


@router.post("", response_model=s.GateEntryRead)
def create_gate_entry(body: s.GateEntryCreate, db: Session = Depends(get_db),
                      user: CurrentUser = Depends(write_guard)):
    return svc.create_entry(db, user, body)


@router.post("/backfill", response_model=s.GateEntryRead)
def create_backfill_entry(body: s.GateBackfillCreate, db: Session = Depends(get_db),
                          user: CurrentUser = Depends(write_guard)):
    return svc.create_backfill(db, user, body)


@router.get("/unmatched", response_model=list[s.GateEntryRead])
def unmatched_folder(db: Session = Depends(get_db),
                     user: CurrentUser = Depends(read_guard)):
    return svc.list_unmatched(db, user)


@router.get("", response_model=list[s.GateEntryRead])
def list_gate_entries(status: str | None = None, match_status: str | None = None,
                      date: dt.date | None = None, limit: int = 200, offset: int = 0,
                      db: Session = Depends(get_db),
                      user: CurrentUser = Depends(read_guard)):
    return svc.list_entries(db, user, status=status, match_status=match_status,
                            date=date, limit=limit, offset=offset)


@router.get("/{entry_id}", response_model=s.GateEntryRead)
def get_gate_entry(entry_id: int, db: Session = Depends(get_db),
                   user: CurrentUser = Depends(read_guard)):
    return svc.get_entry(db, user, entry_id)


@router.post("/{entry_id}/complete-backfill", response_model=s.GateEntryRead)
def complete_backfill(entry_id: int, body: s.GateBackfillComplete,
                      db: Session = Depends(get_db),
                      user: CurrentUser = Depends(write_guard)):
    return svc.complete_backfill(db, user, entry_id, body)


@router.post("/{entry_id}/attach-invoice", response_model=s.GateEntryRead)
def attach_invoice(entry_id: int, body: s.GateAttachInvoice,
                   db: Session = Depends(get_db),
                   user: CurrentUser = Depends(write_guard)):
    return svc.attach_invoice(db, user, entry_id, body)


@router.post("/{entry_id}/link-po", response_model=s.GateEntryRead)
def link_po(entry_id: int, body: s.GateLinkPo, db: Session = Depends(get_db),
            user: CurrentUser = Depends(write_guard)):
    return svc.link_po(db, user, entry_id, body.po_id)


@router.post("/{entry_id}/mark-consumable", response_model=s.GateEntryRead)
def mark_consumable(entry_id: int, db: Session = Depends(get_db),
                    user: CurrentUser = Depends(write_guard)):
    return svc.mark_consumable(db, user, entry_id)
