"""Production models. Spec: Architecture §4.7 (+§11.10, §11.11 deltas)."""
from datetime import date, datetime
from decimal import Decimal
import uuid

from sqlalchemy import (Boolean, CheckConstraint, Date, DateTime, ForeignKey, Index,
                        Integer, SmallInteger, Text, UniqueConstraint, Uuid, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import ArrayVariant, Base, JSONVariant, Money, Qty, created_at, intpk


class ShiftContext(Base):
    """Shift open/close context pinning the plan revision (§11.10)."""

    __tablename__ = "shift_contexts"
    __table_args__ = (
        CheckConstraint("shift IN ('A', 'B')", name="shift"),
        CheckConstraint(
            "close_kind IS NULL OR close_kind IN ('manual', 'auto')", name="close_kind"
        ),
        UniqueConstraint("line_id", "shift_date", "shift"),
    )

    id: Mapped[intpk]
    line_id: Mapped[int] = mapped_column(ForeignKey("lines.id"), nullable=False)
    shift_date: Mapped[date] = mapped_column(Date, nullable=False)
    shift: Mapped[str] = mapped_column(Text, nullable=False)
    plan_revision: Mapped[int] = mapped_column(Integer, nullable=False)
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    close_kind: Mapped[str | None] = mapped_column(Text)


class ProductionConfirmation(Base):
    """Shift production confirmation, interim or shift-close (§4.7 + §11.10 deltas)."""

    __tablename__ = "production_confirmations"
    __table_args__ = (
        CheckConstraint("shift IN ('A', 'B')", name="shift"),
        CheckConstraint("kind IN ('interim', 'shift_close')", name="kind"),
        CheckConstraint("status IN ('posted', 'corrected')", name="status"),
        Index("ix_production_confirmations_line_posted", "line_id", "posted_at"),
    )

    id: Mapped[intpk]
    order_id: Mapped[int] = mapped_column(ForeignKey("production_orders.id"), nullable=False)
    line_id: Mapped[int] = mapped_column(ForeignKey("lines.id"), nullable=False)
    shift: Mapped[str] = mapped_column(Text, nullable=False)
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"), nullable=False)
    good_qty: Mapped[Decimal] = mapped_column(Qty, nullable=False)
    rejected_qty: Mapped[Decimal] = mapped_column(Qty, nullable=False)
    # Required if rejected_qty > 0 — service-enforced (§4.7).
    reject_reason_id: Mapped[int | None] = mapped_column(ForeignKey("reason_codes.id"))
    downtime_min: Mapped[int] = mapped_column(Integer, nullable=False)
    downtime_reason_id: Mapped[int | None] = mapped_column(ForeignKey("reason_codes.id"))
    process_loss: Mapped[dict | None] = mapped_column(JSONVariant)  # {blanking,piercing,forming}
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    client_ref: Mapped[uuid.UUID] = mapped_column(Uuid, unique=True, nullable=False)
    supervisor_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    posted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    # §11.10 deltas.
    shift_context_id: Mapped[int | None] = mapped_column(ForeignKey("shift_contexts.id"))
    posted_after_close: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )


class ConfirmationCorrection(Base):
    """Approved delta correction to a posted confirmation (§4.7)."""

    __tablename__ = "confirmation_corrections"

    id: Mapped[intpk]
    confirmation_id: Mapped[int] = mapped_column(
        ForeignKey("production_confirmations.id"), nullable=False
    )
    delta_good: Mapped[Decimal] = mapped_column(Qty, nullable=False)
    delta_reject: Mapped[Decimal] = mapped_column(Qty, nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    approval_id: Mapped[int] = mapped_column(ForeignKey("approvals.id"), nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)


class ConfirmationHold(Base):
    """'Can't confirm' PPC queue entry holding a full confirmation payload (§11.11)."""

    __tablename__ = "confirmation_holds"
    __table_args__ = (
        CheckConstraint("status IN ('open', 'resolved', 'discarded')", name="status"),
    )

    id: Mapped[intpk]
    line_id: Mapped[int] = mapped_column(ForeignKey("lines.id"), nullable=False)
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"), nullable=False)
    shift_context_id: Mapped[int] = mapped_column(ForeignKey("shift_contexts.id"), nullable=False)
    payload: Mapped[dict] = mapped_column(JSONVariant, nullable=False)  # full confirmation body
    status: Mapped[str] = mapped_column(Text, nullable=False)
    resolved_order_id: Mapped[int | None] = mapped_column(ForeignKey("production_orders.id"))
    client_ref: Mapped[uuid.UUID] = mapped_column(Uuid, unique=True, nullable=False)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[created_at]
