"""Master-data schemas. Read models use from_attributes; create/update models list
ONLY the fields the API allows (immutability enforced by omission + service check)."""
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- materials ---
class MaterialRead(_Read):
    id: int
    sap_code: str
    description: str
    mat_type: str
    mat_group: str | None
    category: str
    uom: str
    price: Decimal | None
    abc: str | None
    is_active: bool
    source: str


class MaterialCreate(BaseModel):
    sap_code: str
    description: str
    mat_type: str = "ROH"
    mat_group: str | None = None
    category: str = "rm"  # rm | component | fg (plant stock-routing category)
    uom: str = "EA"
    price: Decimal | None = None
    abc: str | None = None


class MaterialUpdate(BaseModel):
    description: str | None = None
    mat_group: str | None = None
    category: str | None = None
    uom: str | None = None
    price: Decimal | None = None
    abc: str | None = None
    is_active: bool | None = None


# --- vendors ---
class VendorRead(_Read):
    id: int
    sap_code: str
    name: str
    gstin: str | None
    phone: str | None
    city: str | None
    state: str | None
    credit_limit: Decimal | None
    qty_limit_mt: Decimal | None
    is_active: bool
    source: str


class VendorCreate(BaseModel):
    sap_code: str
    name: str
    gstin: str | None = None
    phone: str | None = None
    city: str | None = None
    state: str | None = None
    credit_limit: Decimal | None = None
    qty_limit_mt: Decimal | None = None


class VendorUpdate(BaseModel):
    name: str | None = None
    gstin: str | None = None
    phone: str | None = None
    city: str | None = None
    state: str | None = None
    credit_limit: Decimal | None = None
    qty_limit_mt: Decimal | None = None
    is_active: bool | None = None


# --- lines / orders / customers ---
class LineRead(_Read):
    id: int
    name: str
    plant: str
    is_active: bool
    material_ids: list[int] = []


class LineCreate(BaseModel):
    name: str
    plant: str = "1117"


class LineUpdate(BaseModel):
    name: str | None = None
    is_active: bool | None = None


class LineMaterialsPut(BaseModel):
    material_ids: list[int]


class ProductionOrderRead(_Read):
    id: int
    sap_order_no: str
    line_id: int | None
    material_id: int | None
    status: str | None


class ProductionOrderCreate(BaseModel):
    sap_order_no: str
    line_id: int
    material_id: int
    status: str = "released"


class ProductionOrderUpdate(BaseModel):
    line_id: int | None = None
    material_id: int | None = None
    status: str | None = None


class CustomerRead(_Read):
    id: int
    sap_code: str | None
    name: str
    gstin: str | None


# --- read-only master ---
class PurchaseOrderRead(_Read):
    id: int
    sap_po_no: str
    item_no: int
    vendor_id: int | None
    material_id: int | None
    ordered_qty: Decimal | None
    open_qty: Decimal | None
    rate: Decimal | None
    uom: str | None
    due_date: datetime | None = None
    status: str | None


class BomLineRead(_Read):
    id: int
    component_material_id: int
    item_no: int | None
    qty_per: Decimal
    uom: str | None
    is_scrap_credit: bool


class BomRead(_Read):
    id: int
    parent_material_id: int
    alt_bom: str | None
    is_active: bool
    lines: list[BomLineRead] = []
