"""Files & gate models. Spec: Architecture §4.5 (+§11.3/11.5/11.6/11.9/11.15 deltas)."""
from datetime import date, datetime
from decimal import Decimal
import uuid

from sqlalchemy import (BigInteger, Boolean, CheckConstraint, Date, DateTime, ForeignKey,
                        Index, SmallInteger, Text, Uuid, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, JSONVariant, Money, Qty, created_at, intpk


class File(Base):
    """Stored binary (scan/photo/import/export) in object storage. §4.5."""
    __tablename__ = "files"
    __table_args__ = (
        CheckConstraint("kind IN ('scan','photo','import','export')", name="kind_valid"),
    )
    id: Mapped[intpk]
    storage_key: Mapped[str] = mapped_column(Text)
    kind: Mapped[str] = mapped_column(Text)
    mime: Mapped[str] = mapped_column(Text)
    size_bytes: Mapped[int] = mapped_column(BigInteger)
    sha256: Mapped[str] = mapped_column(Text)
    uploaded_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))  # agent uploads use a service account
    created_at: Mapped[created_at]


class GateScan(Base):
    """Decoded scanner/phone capture awaiting linkage to a gate entry. §4.5 + §5.7."""
    __tablename__ = "gate_scans"
    __table_args__ = (
        CheckConstraint("source IN ('agent','phone')", name="source_valid"),
        CheckConstraint("decode_status IN ('decoded','partial','none')", name="decode_status_valid"),
        CheckConstraint("hsn_check IN ('ok','mismatch','n/a')", name="hsn_check_valid"),
        CheckConstraint("status IN ('pending','linked','discarded')", name="status_valid"),
    )
    id: Mapped[intpk]
    file_id: Mapped[int] = mapped_column(ForeignKey("files.id"))
    source: Mapped[str] = mapped_column(Text)
    decode_status: Mapped[str] = mapped_column(Text)
    qr_payload: Mapped[dict | None] = mapped_column(JSONVariant)
    pdf417_payload: Mapped[str | None] = mapped_column(Text)
    hsn_check: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    gate_entry_id: Mapped[int | None] = mapped_column(ForeignKey("gate_entries.id"))
    created_at: Mapped[created_at]


class GateEntry(Base):
    """Truck at the gate; doc scanned/keyed; PO matched or unmatched. §4.5 + §11.3/5/6/15."""
    __tablename__ = "gate_entries"
    __table_args__ = (
        CheckConstraint("match_status IN ('matched','unmatched','consumable')", name="match_status_valid"),
        CheckConstraint("status IN ('open','gr_done','cancelled')", name="status_valid"),
        CheckConstraint("entry_mode IN ('live','backfill')", name="entry_mode_valid"),
        CheckConstraint(
            "backfill_status IN ('pending_completion','completed')", name="backfill_status_valid"
        ),
        CheckConstraint(
            "doc_type IN ('invoice','challan','return_gatepass','other_inward')", name="doc_type_valid"
        ),
        CheckConstraint(
            "inward_category IN "
            "('po_supply','customer_return','consumable','repair','job_work_return')",
            name="inward_category_valid",
        ),
        Index(
            "uq_gate_entries_vendor_invoice_consignment",
            "vendor_id", "invoice_no", "consignment_no",
            unique=True,
            postgresql_where=text("doc_type = 'invoice'"),
            sqlite_where=text("doc_type = 'invoice'"),
        ),
        Index(
            "ix_gate_entries_match_status_unmatched",
            "match_status",
            postgresql_where=text("match_status = 'unmatched'"),
            sqlite_where=text("match_status = 'unmatched'"),
        ),
    )
    id: Mapped[intpk]
    doc_no: Mapped[str] = mapped_column(Text, unique=True)  # G-…
    plant: Mapped[str] = mapped_column(Text, default="1117", server_default="1117")
    vendor_id: Mapped[int | None] = mapped_column(ForeignKey("vendors.id"))
    invoice_no: Mapped[str | None] = mapped_column(Text)  # nullable per §11.5 invoice-later
    invoice_date: Mapped[date | None] = mapped_column(Date)
    invoice_value: Mapped[Decimal | None] = mapped_column(Money)
    irn: Mapped[str | None] = mapped_column(Text)
    po_id: Mapped[int | None] = mapped_column(ForeignKey("purchase_orders.id"))
    material_id: Mapped[int | None] = mapped_column(ForeignKey("materials.id"))
    qty_expected: Mapped[Decimal | None] = mapped_column(Qty)
    vehicle_no: Mapped[str] = mapped_column(Text)
    driver_name: Mapped[str] = mapped_column(Text)
    vehicle_photo_id: Mapped[int | None] = mapped_column(ForeignKey("files.id"))
    invoice_photo_id: Mapped[int | None] = mapped_column(ForeignKey("files.id"))
    match_status: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="open", server_default="open")
    entry_mode: Mapped[str] = mapped_column(Text, default="live", server_default="live")  # §11.3
    backfill_status: Mapped[str | None] = mapped_column(Text)  # §11.3
    vendor_name_text: Mapped[str | None] = mapped_column(Text)  # §11.3 offline free-text vendor
    doc_type: Mapped[str] = mapped_column(Text, default="invoice", server_default="invoice")  # §11.5
    inward_category: Mapped[str | None] = mapped_column(Text)  # §11.5
    consignment_no: Mapped[int] = mapped_column(SmallInteger, default=1, server_default="1")  # §11.6
    consignment_total: Mapped[int | None] = mapped_column(SmallInteger)  # §11.6
    photos_pending: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=text("false")
    )  # §11.15
    client_ref: Mapped[uuid.UUID] = mapped_column(Uuid, unique=True)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[created_at]


class ReturnGatePass(Base):
    """Outbound pass for a fully rejected lot leaving the plant. §11.9."""
    __tablename__ = "return_gate_passes"
    __table_args__ = (
        CheckConstraint("status IN ('issued','vehicle_left','cancelled')", name="status_valid"),
    )
    id: Mapped[intpk]
    doc_no: Mapped[str] = mapped_column(Text, unique=True)  # RGP-…
    goods_receipt_id: Mapped[int] = mapped_column(ForeignKey("goods_receipts.id"))
    gate_entry_id: Mapped[int] = mapped_column(ForeignKey("gate_entries.id"))
    vehicle_no: Mapped[str] = mapped_column(Text)
    reason: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="issued", server_default="issued")
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[created_at]
