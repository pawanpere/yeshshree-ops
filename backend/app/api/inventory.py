"""Stock + issues + corrections router (P23/P24/P27). HTTP concerns ONLY — all
business logic lives in services/inventory.py + services/issuing.py (CLAUDE.md).
NOTE: register in app/main.py with `app.include_router(inventory_router)` —
wiring main.py is outside this packet's file list (tests mount it themselves)."""
from fastapi import APIRouter, Depends, Query, UploadFile
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.models.inventory import Issue
from app.models.master import Vendor
from app.schemas import inventory as s
from app.services import inventory as inv
from app.services import issuing
from app.services.master import get_or_404

router = APIRouter(prefix="/api/v1", tags=["inventory"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
read_guard = require(*INTERNAL)


def _issue_read(issue: Issue) -> s.IssueRead:
    out = s.IssueRead.model_validate(issue)
    out.stock_warning = bool((issue.limit_check or {}).get("stock", {}).get("warned"))
    return out


# --- stock (P23) ---
@router.get("/stock/balances", response_model=list[s.BalanceRead])
def stock_balances(material_id: int | None = Query(None),
                   location: str | None = Query(None),
                   vendor_id: int | None = Query(None),
                   db: Session = Depends(get_db),
                   _: CurrentUser = Depends(read_guard)):
    return inv.balances(db, material_id=material_id, location=location,
                        vendor_id=vendor_id)


@router.get("/stock/days-of-cover/{material_id}", response_model=s.DaysOfCoverRead)
def stock_days_of_cover(material_id: int, db: Session = Depends(get_db),
                        _: CurrentUser = Depends(read_guard)):
    return s.DaysOfCoverRead(material_id=material_id,
                             days_of_cover=inv.days_of_cover(db, material_id))


@router.post("/imports/sap-stock", response_model=s.SapStockImportResult)
async def import_sap_stock(file: UploadFile, db: Session = Depends(get_db),
                           user: CurrentUser = Depends(require("admin", "planning"))):
    """SAP stock snapshot → import_jobs(kind='sap_stock') + ADJUST reconcile (§11.1)."""
    content = await file.read()
    return inv.import_sap_stock(db, user, content=content,
                                filename=file.filename or "sap_stock",
                                mime=file.content_type)


# --- issues (P24) ---
@router.post("/issues", response_model=s.IssueRead)
def post_issue(body: s.IssueCreate, db: Session = Depends(get_db),
               user: CurrentUser = Depends(require("plant_ops", "admin"))):
    """200 (not 201): a retried client_ref returns the ORIGINAL result (invariant 4)."""
    return _issue_read(issuing.post_issue(db, user, body))


@router.get("/issues", response_model=list[s.IssueRead])
def list_issues(status: str | None = Query(None), vendor_id: int | None = Query(None),
                destination: str | None = Query(None),
                limit: int = 200, offset: int = 0,
                db: Session = Depends(get_db),
                _: CurrentUser = Depends(read_guard)):
    q = db.query(Issue)
    if status:
        q = q.filter_by(status=status)
    if vendor_id:
        q = q.filter_by(vendor_id=vendor_id)
    if destination:
        q = q.filter_by(destination=destination)
    rows = q.order_by(Issue.id.desc()).limit(limit).offset(offset).all()
    return [_issue_read(r) for r in rows]


@router.get("/issues/{issue_id}", response_model=s.IssueRead)
def get_issue(issue_id: int, db: Session = Depends(get_db),
              _: CurrentUser = Depends(read_guard)):
    return _issue_read(get_or_404(db, Issue, issue_id, "issue"))


# --- corrections (P27) ---
@router.post("/issues/{issue_id}/correction", response_model=s.CorrectionRead)
def request_correction(issue_id: int, body: s.CorrectionCreate,
                       db: Session = Depends(get_db),
                       user: CurrentUser = Depends(
                           require("plant_ops", "supervisor", "admin"))):
    return issuing.request_correction(db, user, issue_id,
                                      body.corrected.model_dump(exclude_none=True),
                                      body.reason)


# --- vendor exposure (§5.5a, internal read) ---
@router.get("/vendors/{vendor_id}/exposure", response_model=s.ExposureRead)
def vendor_exposure(vendor_id: int, db: Session = Depends(get_db),
                    _: CurrentUser = Depends(read_guard)):
    vendor = get_or_404(db, Vendor, vendor_id, "vendor")
    exp = issuing.vendor_exposure(db, vendor_id)
    return s.ExposureRead(vendor_id=vendor_id, credit_exposure=exp["credit_exposure"],
                          qty_mt=exp["qty_mt"], credit_limit=vendor.credit_limit,
                          qty_limit_mt=vendor.qty_limit_mt)
