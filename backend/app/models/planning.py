"""Planning models. Spec: Architecture §4.4 (+§11.13 deltas)."""
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (CheckConstraint, Date, DateTime, ForeignKey, Index, Integer,
                        Text, UniqueConstraint)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, JSONVariant, Qty, created_at, intpk


class Schedule(Base):
    """Customer schedule import; versioned, released by planner. §4.4 + §11.13 sanity."""
    __tablename__ = "schedules"
    __table_args__ = (
        CheckConstraint("status IN ('draft','released','superseded')", name="status_valid"),
        UniqueConstraint("customer_id", "period", "version",
                         name="uq_schedules_customer_period_version"),
    )
    id: Mapped[intpk]
    customer_id: Mapped[int] = mapped_column(ForeignKey("customers.id"))
    period: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(Text, default="draft", server_default="draft")
    source_file_id: Mapped[int | None] = mapped_column(ForeignKey("files.id"))
    diff: Mapped[dict] = mapped_column(JSONVariant)
    sanity: Mapped[dict | None] = mapped_column(JSONVariant)  # §11.13 release sanity checks
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    released_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    released_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ScheduleLine(Base):
    """One bucketed quantity row of a schedule version. §4.4."""
    __tablename__ = "schedule_lines"
    id: Mapped[intpk]
    schedule_id: Mapped[int] = mapped_column(ForeignKey("schedules.id"))
    model_family: Mapped[str] = mapped_column(Text)
    material_id: Mapped[int | None] = mapped_column(ForeignKey("materials.id"))
    bucket_date: Mapped[date] = mapped_column(Date)
    qty: Mapped[Decimal] = mapped_column(Qty)


class LinePlan(Base):
    """Per-line daily plan; regenerated on each release, old revision kept. §4.4."""
    __tablename__ = "line_plans"
    __table_args__ = (
        CheckConstraint("status IN ('active','superseded')", name="status_valid"),
        Index("ix_line_plans_plan_date_line_id", "plan_date", "line_id"),
    )
    id: Mapped[intpk]
    plan_date: Mapped[date] = mapped_column(Date)
    line_id: Mapped[int] = mapped_column(ForeignKey("lines.id"))
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    planned_qty: Mapped[Decimal] = mapped_column(Qty)
    schedule_id: Mapped[int] = mapped_column(ForeignKey("schedules.id"))
    revision: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(Text, default="active", server_default="active")


class VendorCalloff(Base):
    """Vendor call-off derived from a released schedule. §4.4."""
    __tablename__ = "vendor_calloffs"
    id: Mapped[intpk]
    vendor_id: Mapped[int] = mapped_column(ForeignKey("vendors.id"))
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id"))
    calloff_date: Mapped[date] = mapped_column(Date)
    qty: Mapped[Decimal] = mapped_column(Qty)
    schedule_id: Mapped[int] = mapped_column(ForeignKey("schedules.id"))
    status: Mapped[str] = mapped_column(Text)  # spec gives no CHECK values for this status
