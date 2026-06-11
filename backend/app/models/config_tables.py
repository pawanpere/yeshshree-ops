"""Config models — admin-editable, every change audit-logged. Spec: Architecture §4.3 (+§11.7 tolerances)."""
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (BigInteger, Boolean, CheckConstraint, Date, DateTime, Integer,
                        Numeric, SmallInteger, Text, UniqueConstraint, func)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, JSONVariant, Qty, intpk


class ModelFamilySplit(Base):
    """Yeshshree/Laxmi percentage split per model family, effective-dated. §4.3."""
    __tablename__ = "model_family_splits"
    id: Mapped[intpk]
    family: Mapped[str] = mapped_column(Text)
    yesh_pct: Mapped[int] = mapped_column(SmallInteger)
    laxmi_pct: Mapped[int] = mapped_column(SmallInteger)
    effective_from: Mapped[date] = mapped_column(Date)


class ReasonCode(Base):
    """Bilingual reject/downtime reason codes shown on station screens. §4.3."""
    __tablename__ = "reason_codes"
    __table_args__ = (
        CheckConstraint("kind IN ('reject','downtime')", name="kind_valid"),
    )
    id: Mapped[intpk]
    kind: Mapped[str] = mapped_column(Text)
    code: Mapped[str] = mapped_column(Text, unique=True)
    label_en: Mapped[str] = mapped_column(Text)
    label_mr: Mapped[str] = mapped_column(Text)
    sort: Mapped[int] = mapped_column(SmallInteger)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")


class Mill(Base):
    """Steel mill config — config screen now; mill-flag logic post-MVP. §4.3."""
    __tablename__ = "mills"
    id: Mapped[intpk]
    name: Mapped[str] = mapped_column(Text)
    lead_days: Mapped[int] = mapped_column(Integer)
    moq_mt: Mapped[Decimal] = mapped_column(Qty)
    sourcing: Mapped[str | None] = mapped_column(Text)


class PlanCalendar(Base):
    """Working-day calendar with per-day shift definitions. §4.3."""
    __tablename__ = "plan_calendar"
    cal_date: Mapped[date] = mapped_column(Date, primary_key=True)
    is_working: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    shifts: Mapped[dict[str, Any] | None] = mapped_column(JSONVariant)


class AppSetting(Base):
    """Key/value settings: anomaly thresholds, debit multiplier, GR target minutes, ops_mode. §4.3 (+§11.1)."""
    __tablename__ = "app_settings"
    key: Mapped[str] = mapped_column(Text, primary_key=True)
    value: Mapped[dict[str, Any]] = mapped_column(JSONVariant)
    description: Mapped[str | None] = mapped_column(Text)
    updated_by: Mapped[int | None] = mapped_column(BigInteger)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class DocSequence(Base):
    """G/GR/ISS/DN/RGP number allocator, read under SELECT ... FOR UPDATE. §4.3 (+§11.9 RGP)."""
    __tablename__ = "doc_sequences"
    doc_type: Mapped[str] = mapped_column(Text, primary_key=True)
    fiscal_year: Mapped[str] = mapped_column(Text, primary_key=True)
    next_no: Mapped[int] = mapped_column(Integer, default=1, server_default="1")


class MaterialGroupTolerance(Base):
    """QC qty tolerance per material group + uom; in-tolerance GRs accept clean. §11.7."""
    __tablename__ = "material_group_tolerances"
    __table_args__ = (
        UniqueConstraint("mat_group", "uom"),
    )
    id: Mapped[intpk]
    mat_group: Mapped[str] = mapped_column(Text)
    uom: Mapped[str] = mapped_column(Text)
    pct_tolerance: Mapped[Decimal] = mapped_column(Numeric(5, 2))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
