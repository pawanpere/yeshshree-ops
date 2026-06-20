"""Vendor-portal read schemas (Phase 6). A vendor sees ONLY their own data; the
scoping is enforced in the service layer from the JWT vendor_id (invariant 5), never
from a client-supplied id. Money/qty are Decimal (serialized as strings)."""
from datetime import date
from decimal import Decimal

from pydantic import BaseModel


class VendorOrderRead(BaseModel):
    id: int
    sap_po_no: str
    item_no: int
    material_id: int
    material: str
    ordered_qty: Decimal
    open_qty: Decimal
    rate: Decimal | None
    uom: str
    due_date: date | None
    status: str


class VendorCalloffRead(BaseModel):
    id: int
    material_id: int
    material: str
    calloff_date: date
    qty: Decimal
    status: str


class VendorDebitNoteRead(BaseModel):
    id: int
    doc_no: str
    kind: str
    base_amount: Decimal
    amount: Decimal
    status: str


class VendorStockRead(BaseModel):
    material_id: int
    material: str
    qty: Decimal
    uom: str
