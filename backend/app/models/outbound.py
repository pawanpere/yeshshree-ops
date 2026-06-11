"""Outbound (dispatch & sales invoice) models. Spec: Architecture §4.7."""
from datetime import date, datetime
from decimal import Decimal
import uuid

from sqlalchemy import (Boolean, CheckConstraint, Date, DateTime, ForeignKey, Index,
                        Integer, SmallInteger, Text, UniqueConstraint, Uuid, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import ArrayVariant, Base, JSONVariant, Money, Qty, created_at, intpk


class Dispatch(Base):
    """Outbound dispatch header (DN-…) (§4.7)."""

    __tablename__ = "dispatches"
    __table_args__ = (
        CheckConstraint("status IN ('open', 'invoiced', 'cancelled')", name="status"),
    )

    id: Mapped[intpk]
    doc_no: Mapped[str] = mapped_column(Text, nullable=False)
    customer_id: Mapped[int] = mapped_column(ForeignKey("customers.id"), nullable=False)
    vehicle_no: Mapped[str] = mapped_column(Text, nullable=False)
    total_pcs: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    client_ref: Mapped[uuid.UUID] = mapped_column(Uuid, unique=True, nullable=False)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[created_at]


class DispatchLine(Base):
    """Material/qty line of a dispatch (§4.7)."""

    __tablename__ = "dispatch_lines"

    id: Mapped[intpk]
    dispatch_id: Mapped[int] = mapped_column(ForeignKey("dispatches.id"), nullable=False)
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"), nullable=False)
    qty: Mapped[Decimal] = mapped_column(Qty, nullable=False)


class SalesInvoice(Base):
    """Sales invoice matched against a dispatch (§4.7)."""

    __tablename__ = "sales_invoices"
    __table_args__ = (
        CheckConstraint("match_status IN ('ok', 'mismatch')", name="match_status"),
        CheckConstraint("status IN ('pending', 'confirmed')", name="status"),
    )

    id: Mapped[intpk]
    invoice_no: Mapped[str] = mapped_column(Text, nullable=False)
    invoice_date: Mapped[date] = mapped_column(Date, nullable=False)
    dispatch_id: Mapped[int] = mapped_column(ForeignKey("dispatches.id"), nullable=False)
    irn: Mapped[str | None] = mapped_column(Text)
    eway_bill_no: Mapped[str | None] = mapped_column(Text)
    total_value: Mapped[Decimal] = mapped_column(Money, nullable=False)
    match_status: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    confirmed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    client_ref: Mapped[uuid.UUID] = mapped_column(Uuid, unique=True, nullable=False)


class SalesInvoiceLine(Base):
    """Material/qty/value line of a sales invoice (§4.7)."""

    __tablename__ = "sales_invoice_lines"

    id: Mapped[intpk]
    invoice_id: Mapped[int] = mapped_column(ForeignKey("sales_invoices.id"), nullable=False)
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"), nullable=False)
    qty: Mapped[Decimal] = mapped_column(Qty, nullable=False)
    value: Mapped[Decimal] = mapped_column(Money, nullable=False)
