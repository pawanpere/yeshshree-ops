"""Inward, stock & issue models. Spec: Architecture §4.6 (+§11.9/11.12 deltas)."""
from datetime import datetime
from decimal import Decimal
import uuid

from sqlalchemy import (BigInteger, CheckConstraint, DateTime, ForeignKey, Index, Numeric,
                        Text, Uuid, func)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, JSONVariant, Money, Qty, created_at, intpk


class GoodsReceipt(Base):
    """GR against a gate entry; QC result drives shortage/debit flow. §4.6."""
    __tablename__ = "goods_receipts"
    __table_args__ = (
        CheckConstraint("qc_result IN ('pass','fail')", name="qc_result_valid"),
        CheckConstraint("status IN ('posted','cancelled')", name="status_valid"),
    )
    id: Mapped[intpk]
    doc_no: Mapped[str] = mapped_column(Text, unique=True)  # GR-…
    gate_entry_id: Mapped[int] = mapped_column(ForeignKey("gate_entries.id"))
    po_id: Mapped[int | None] = mapped_column(ForeignKey("purchase_orders.id"))
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    expected_qty: Mapped[Decimal] = mapped_column(Qty)
    received_qty: Mapped[Decimal] = mapped_column(Qty)
    accepted_qty: Mapped[Decimal] = mapped_column(Qty)
    rejected_qty: Mapped[Decimal] = mapped_column(Qty)
    qc_result: Mapped[str] = mapped_column(Text)
    qc_remarks: Mapped[str | None] = mapped_column(Text)
    shortage_qty: Mapped[Decimal] = mapped_column(Qty)
    status: Mapped[str] = mapped_column(Text, default="posted", server_default="posted")
    client_ref: Mapped[uuid.UUID] = mapped_column(Uuid, unique=True)
    posted_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    posted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DebitNote(Base):
    """Shortage 5x / full-lot-reject debit against a vendor GR. §4.6 + §11.9."""
    __tablename__ = "debit_notes"
    __table_args__ = (
        CheckConstraint("kind IN ('shortage_5x','full_lot_reject')", name="kind_valid"),
        CheckConstraint("status IN ('draft','approved','declined','raised')", name="status_valid"),
    )
    id: Mapped[intpk]
    doc_no: Mapped[str] = mapped_column(Text, unique=True)  # DN-…
    goods_receipt_id: Mapped[int] = mapped_column(ForeignKey("goods_receipts.id"))
    vendor_id: Mapped[int] = mapped_column(ForeignKey("vendors.id"))
    kind: Mapped[str] = mapped_column(Text)
    base_amount: Mapped[Decimal] = mapped_column(Money)
    multiplier: Mapped[Decimal] = mapped_column(Numeric(5, 2))
    amount: Mapped[Decimal] = mapped_column(Money)
    status: Mapped[str] = mapped_column(Text, default="draft", server_default="draft")
    approval_id: Mapped[int | None] = mapped_column(ForeignKey("approvals.id"))


class StockLedger(Base):
    """Append-only signed movements; the only way stock changes. §4.6."""
    __tablename__ = "stock_ledger"
    __table_args__ = (
        CheckConstraint("location IN ('RM','WIP','FG','AT_VENDOR')", name="location_valid"),
        CheckConstraint(
            "movement IN ('GR_IN','ISSUE_OUT','PROD_IN','PROD_CONSUME','DISPATCH_OUT','ADJUST')",
            name="movement_valid",
        ),
        Index("ix_stock_ledger_material_location", "material_id", "location"),
    )
    id: Mapped[intpk]
    plant: Mapped[str] = mapped_column(Text, default="1117", server_default="1117")
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    location: Mapped[str] = mapped_column(Text)
    movement: Mapped[str] = mapped_column(Text)
    qty: Mapped[Decimal] = mapped_column(Qty)  # signed
    uom: Mapped[str] = mapped_column(Text)
    vendor_id: Mapped[int | None] = mapped_column(ForeignKey("vendors.id"))
    ref_type: Mapped[str] = mapped_column(Text)
    ref_id: Mapped[int] = mapped_column(BigInteger)
    # NULL for system-written movements (SAP stock reconcile, worker-applied corrections);
    # the human actor lives on the source doc (ref_type/ref_id) and in audit_log.
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[created_at]


class Issue(Base):
    """Material issue to line / vendor sale / job work, credit-limit checked. §4.6 + §11.12."""
    __tablename__ = "issues"
    __table_args__ = (
        CheckConstraint("destination IN ('inhouse','vendor_sale','job_work')", name="destination_valid"),
        CheckConstraint(
            "status IN ('posted','blocked','waiver_pending','cancelled','corrected')",
            name="status_valid",
        ),
    )
    id: Mapped[intpk]
    doc_no: Mapped[str] = mapped_column(Text, unique=True)  # ISS-…
    destination: Mapped[str] = mapped_column(Text)
    line_id: Mapped[int | None] = mapped_column(ForeignKey("lines.id"))
    vendor_id: Mapped[int | None] = mapped_column(ForeignKey("vendors.id"))
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    qty: Mapped[Decimal] = mapped_column(Qty)
    uom: Mapped[str] = mapped_column(Text)
    value: Mapped[Decimal] = mapped_column(Money)
    limit_check: Mapped[dict] = mapped_column(JSONVariant)  # snapshot of the check at decision time
    status: Mapped[str] = mapped_column(Text)
    approval_id: Mapped[int | None] = mapped_column(ForeignKey("approvals.id"))
    client_ref: Mapped[uuid.UUID] = mapped_column(Uuid, unique=True)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[created_at]


class IssueCorrection(Base):
    """Approved reversal + repost of a wrong issue; never a silent edit. §11.12."""
    __tablename__ = "issue_corrections"
    __table_args__ = (
        CheckConstraint("status IN ('pending','applied','declined')", name="status_valid"),
    )
    id: Mapped[intpk]
    issue_id: Mapped[int] = mapped_column(ForeignKey("issues.id"))
    corrected: Mapped[dict] = mapped_column(JSONVariant)  # new material/qty/destination
    reason: Mapped[str] = mapped_column(Text)
    approval_id: Mapped[int] = mapped_column(ForeignKey("approvals.id"))
    status: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
