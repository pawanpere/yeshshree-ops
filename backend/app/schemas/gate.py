"""Gate entry schemas (P16+P18). Spec: Architecture §4.5 + §11.3/11.5/11.6.
Read model mirrors the GateEntry columns; write models list only client-settable
fields — doc_no/status/match_status are always server-assigned."""
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict

DocType = Literal["invoice", "challan", "return_gatepass", "other_inward"]
InwardCategory = Literal["po_supply", "customer_return", "consumable", "repair"]


class GateEntryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    doc_no: str
    plant: str
    vendor_id: int | None
    invoice_no: str | None
    invoice_date: date | None
    invoice_value: Decimal | None
    irn: str | None
    po_id: int | None
    material_id: int | None
    qty_expected: Decimal | None
    vehicle_no: str
    driver_name: str
    vehicle_photo_id: int | None
    invoice_photo_id: int | None
    match_status: str
    status: str
    entry_mode: str
    backfill_status: str | None
    vendor_name_text: str | None
    doc_type: str
    inward_category: str | None
    consignment_no: int
    consignment_total: int | None
    photos_pending: bool
    client_ref: uuid.UUID
    created_by: int
    created_at: datetime


class GateEntryCreate(BaseModel):
    client_ref: uuid.UUID
    doc_type: DocType = "invoice"
    inward_category: InwardCategory | None = None
    vendor_id: int | None = None
    invoice_no: str | None = None
    invoice_date: date | None = None
    invoice_value: Decimal | None = None
    irn: str | None = None
    po_id: int | None = None
    material_id: int | None = None
    qty_expected: Decimal | None = None
    vehicle_no: str
    driver_name: str
    consignment_no: int = 1
    consignment_total: int | None = None


class GateBackfillCreate(BaseModel):
    """§11.3 minimal offline entry — trucks proceed, paper register continues."""
    client_ref: uuid.UUID
    vehicle_no: str
    driver_name: str
    vendor_name_text: str
    entered_at: datetime | None = None


class GateBackfillComplete(BaseModel):
    """§11.3 completion — fills the real document data, runs the same PO match."""
    doc_type: DocType = "invoice"
    inward_category: InwardCategory | None = None
    vendor_id: int | None = None
    invoice_no: str | None = None
    invoice_date: date | None = None
    invoice_value: Decimal | None = None
    irn: str | None = None
    po_id: int | None = None
    material_id: int | None = None
    qty_expected: Decimal | None = None
    consignment_no: int = 1
    consignment_total: int | None = None


class GateAttachInvoice(BaseModel):
    """§11.5 invoice-later for challan entries."""
    invoice_no: str
    invoice_date: date | None = None
    invoice_value: Decimal | None = None
    irn: str | None = None


class GateLinkPo(BaseModel):
    po_id: int
