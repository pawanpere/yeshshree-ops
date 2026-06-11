"""Stock / issue / correction schemas (P23/P24/P27). Decimal everywhere — never float
(CLAUDE.md invariant 9). Read models use from_attributes; create models list ONLY the
fields the API accepts (doc_no, value, status, limit_check are server-computed)."""
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- stock (P23) ---
class BalanceRead(BaseModel):
    material_id: int
    location: str
    vendor_id: int | None = None  # set only for AT_VENDOR rows (§4.6)
    qty: Decimal


class DaysOfCoverRead(BaseModel):
    material_id: int
    days_of_cover: Decimal | None  # None = no consumption history (never a fake number)


class SapStockImportResult(BaseModel):
    import_job_id: int
    rows_total: int
    rows_ok: int
    rows_failed: int
    adjustments: int  # ADJUST ledger rows written


# --- issues (P24) ---
class IssueCreate(BaseModel):
    destination: Literal["inhouse", "vendor_sale", "job_work"]
    material_id: int
    qty: Decimal
    uom: str | None = None  # optional; must match the material master when given
    line_id: int | None = None
    vendor_id: int | None = None  # required for vendor_sale / job_work
    client_ref: uuid.UUID


class IssueRead(_Read):
    id: int
    doc_no: str
    destination: str
    line_id: int | None
    vendor_id: int | None
    material_id: int
    qty: Decimal
    uom: str
    value: Decimal
    limit_check: dict  # frozen decision-time snapshot (stock + limits + breaches)
    status: str
    approval_id: int | None
    created_by: int
    created_at: datetime
    stock_warning: bool = False  # §11.1 parallel-run warn flag (derived, see router)


class ExposureRead(BaseModel):
    vendor_id: int
    credit_exposure: Decimal  # §5.5a Σ(AT_VENDOR qty × price)
    qty_mt: Decimal           # Σ(AT_VENDOR KG qty)/1000 — non-KG skipped (documented)
    credit_limit: Decimal | None
    qty_limit_mt: Decimal | None


# --- corrections (P27) ---
class CorrectedFields(BaseModel):
    material_id: int | None = None
    qty: Decimal | None = None
    destination: Literal["inhouse", "vendor_sale", "job_work"] | None = None
    line_id: int | None = None
    vendor_id: int | None = None


class CorrectionCreate(BaseModel):
    corrected: CorrectedFields
    reason: str


class CorrectionRead(_Read):
    id: int
    issue_id: int
    corrected: dict
    reason: str
    approval_id: int
    status: str
