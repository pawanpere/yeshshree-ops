"""Vendor-portal router (Phase 6). Every route requires role='vendor' AND scopes to
the caller's own vendor_id in the service layer (invariant 5). A vendor can never read
another vendor's data — there is no vendor_id path/query param to tamper with."""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.schemas import vendor as s
from app.schemas.inventory import ExposureRead
from app.services import vendor_portal

router = APIRouter(prefix="/api/v1/vendor", tags=["vendor"])

vendor_guard = require("vendor")


@router.get("/purchase-orders", response_model=list[s.VendorOrderRead])
def purchase_orders(db: Session = Depends(get_db),
                    user: CurrentUser = Depends(vendor_guard)):
    return vendor_portal.my_purchase_orders(db, user)


@router.get("/calloffs", response_model=list[s.VendorCalloffRead])
def calloffs(db: Session = Depends(get_db),
             user: CurrentUser = Depends(vendor_guard)):
    return vendor_portal.my_calloffs(db, user)


@router.get("/exposure", response_model=ExposureRead)
def exposure(db: Session = Depends(get_db),
             user: CurrentUser = Depends(vendor_guard)):
    return vendor_portal.my_exposure(db, user)


@router.get("/debit-notes", response_model=list[s.VendorDebitNoteRead])
def debit_notes(db: Session = Depends(get_db),
                user: CurrentUser = Depends(vendor_guard)):
    return vendor_portal.my_debit_notes(db, user)


@router.get("/stock", response_model=list[s.VendorStockRead])
def stock(db: Session = Depends(get_db),
          user: CurrentUser = Depends(vendor_guard)):
    return vendor_portal.my_stock(db, user)
