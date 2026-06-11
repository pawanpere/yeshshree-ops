"""Outbound (dispatch + sales invoice) schemas (P34). Decimal everywhere — never
float (CLAUDE.md invariant 9). Read models use from_attributes; create models list
ONLY the fields the API accepts (doc_no, total_pcs, match_status, status are
server-computed; the invoice itself comes from SAP — Domain_QA Q2)."""
import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- dispatches ---
class DispatchLineIn(BaseModel):
    material_id: int
    qty: Decimal


class DispatchCreate(BaseModel):
    customer_id: int
    vehicle_no: str
    lines: list[DispatchLineIn]
    client_ref: uuid.UUID


class DispatchLineRead(_Read):
    id: int
    material_id: int
    qty: Decimal


class DispatchRead(_Read):
    id: int
    doc_no: str
    customer_id: int
    vehicle_no: str
    total_pcs: int
    status: str
    created_by: int
    created_at: datetime
    lines: list[DispatchLineRead] = []
    stock_warning: bool = False  # §11.1 parallel-run warn flag (derived, see router)


# --- sales invoices (recorded from SAP, Domain_QA Q2) ---
class InvoiceLineIn(BaseModel):
    material_id: int
    qty: Decimal
    value: Decimal


class InvoiceCreate(BaseModel):
    invoice_no: str          # SAP invoice number — keyed/imported, never generated
    invoice_date: date
    dispatch_id: int
    irn: str | None = None
    eway_bill_no: str | None = None
    total_value: Decimal
    lines: list[InvoiceLineIn]
    mismatch_reason: str | None = None  # REQUIRED when qtys differ from the dispatch
    client_ref: uuid.UUID


class InvoiceLineRead(_Read):
    id: int
    material_id: int
    qty: Decimal
    value: Decimal


class InvoiceRead(_Read):
    id: int
    invoice_no: str
    invoice_date: date
    dispatch_id: int
    irn: str | None
    eway_bill_no: str | None
    total_value: Decimal
    match_status: str
    status: str
    confirmed_by: int | None
    confirmed_at: datetime | None
    lines: list[InvoiceLineRead] = []
