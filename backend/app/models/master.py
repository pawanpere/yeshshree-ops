"""Master data models, seeded from SAP exports. Spec: Architecture §4.2 (+§11.15 `source` on materials/vendors)."""
from datetime import date
from decimal import Decimal

from sqlalchemy import (Boolean, CheckConstraint, Date, ForeignKey, Integer, Text,
                        UniqueConstraint)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, Money, Qty, intpk


class Vendor(Base):
    """Supplier master; soft-deleted via is_active, never deleted. §4.2 (+§11.15 source)."""
    __tablename__ = "vendors"
    __table_args__ = (
        CheckConstraint("source IN ('sap_import','manual')", name="source_valid"),
    )
    id: Mapped[intpk]
    sap_code: Mapped[str] = mapped_column(Text, unique=True)
    name: Mapped[str] = mapped_column(Text)
    gstin: Mapped[str | None] = mapped_column(Text)
    phone: Mapped[str | None] = mapped_column(Text)
    city: Mapped[str | None] = mapped_column(Text)
    state: Mapped[str | None] = mapped_column(Text)
    credit_limit: Mapped[Decimal | None] = mapped_column(Money)
    qty_limit_mt: Mapped[Decimal | None] = mapped_column(Qty)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    source: Mapped[str] = mapped_column(Text, default="sap_import", server_default="sap_import")


class Material(Base):
    """Material master (RM/semi-finished/finished). §4.2 (+§11.15 source)."""
    __tablename__ = "materials"
    __table_args__ = (
        # mat_type deliberately UNconstrained: SAP owns this vocabulary (real plant-1117
        # export contains ERSA, HIBE, ROH1, LEIH, ZCDT, ZSCP, ZCAP…). We never CHECK
        # vocabularies an external system controls. Found by golden-file test, 2026-06-11.
        CheckConstraint("source IN ('sap_import','manual')", name="source_valid"),
    )
    id: Mapped[intpk]
    sap_code: Mapped[str] = mapped_column(Text, unique=True)
    description: Mapped[str] = mapped_column(Text)
    mat_type: Mapped[str] = mapped_column(Text)
    mat_group: Mapped[str | None] = mapped_column(Text)
    uom: Mapped[str] = mapped_column(Text)
    price: Mapped[Decimal | None] = mapped_column(Money)
    abc: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    source: Mapped[str] = mapped_column(Text, default="sap_import", server_default="sap_import")


class Bom(Base):
    """BOM header per parent material + alternative. §4.2."""
    __tablename__ = "boms"
    id: Mapped[intpk]
    parent_material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    alt_bom: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")


class BomLine(Base):
    """BOM component line; is_scrap_credit marks negative lines in the real export. §4.2."""
    __tablename__ = "bom_lines"
    id: Mapped[intpk]
    bom_id: Mapped[int] = mapped_column(ForeignKey("boms.id"))
    component_material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    item_no: Mapped[int] = mapped_column(Integer)
    qty_per: Mapped[Decimal] = mapped_column(Qty)
    uom: Mapped[str] = mapped_column(Text)
    is_scrap_credit: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")


class PurchaseOrder(Base):
    """Open PO line from SAP; one row per (sap_po_no, item_no). §4.2."""
    __tablename__ = "purchase_orders"
    __table_args__ = (
        UniqueConstraint("sap_po_no", "item_no"),
    )
    id: Mapped[intpk]
    sap_po_no: Mapped[str] = mapped_column(Text)
    item_no: Mapped[int] = mapped_column(Integer)
    vendor_id: Mapped[int] = mapped_column(ForeignKey("vendors.id"))
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    ordered_qty: Mapped[Decimal] = mapped_column(Qty)
    open_qty: Mapped[Decimal] = mapped_column(Qty)
    rate: Mapped[Decimal | None] = mapped_column(Money)
    uom: Mapped[str] = mapped_column(Text)
    due_date: Mapped[date | None] = mapped_column(Date)
    status: Mapped[str] = mapped_column(Text)


class Line(Base):
    """Production line master. §4.2."""
    __tablename__ = "lines"
    id: Mapped[intpk]
    name: Mapped[str] = mapped_column(Text)
    plant: Mapped[str] = mapped_column(Text, default="1117", server_default="1117")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")


class LineMaterial(Base):
    """Which materials run on which line; composite PK association. §4.2."""
    __tablename__ = "line_materials"
    line_id: Mapped[int] = mapped_column(ForeignKey("lines.id"), primary_key=True)
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"), primary_key=True)


class ProductionOrder(Base):
    """SAP production order; confirmations resolve against it. §4.2."""
    __tablename__ = "production_orders"
    id: Mapped[intpk]
    sap_order_no: Mapped[str] = mapped_column(Text, unique=True)
    line_id: Mapped[int] = mapped_column(ForeignKey("lines.id"))
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    status: Mapped[str] = mapped_column(Text)


class Customer(Base):
    """Customer master — Bajaj now; table, not hardcode. §4.2."""
    __tablename__ = "customers"
    id: Mapped[intpk]
    sap_code: Mapped[str] = mapped_column(Text)
    name: Mapped[str] = mapped_column(Text)
    gstin: Mapped[str | None] = mapped_column(Text)
