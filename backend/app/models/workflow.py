"""Workflow models (approvals, anomalies, notifications, escalations).
Spec: Architecture §4.8 (+§11.2, §11.8, §11.14 deltas)."""
from datetime import date, datetime
from decimal import Decimal
import uuid

from sqlalchemy import (BigInteger, Boolean, CheckConstraint, Date, DateTime, ForeignKey,
                        Index, Integer, SmallInteger, Text, UniqueConstraint, Uuid, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import ArrayVariant, Base, JSONVariant, Money, Qty, created_at, intpk


class Approval(Base):
    """Approval request, co-approval via decisions per role (§4.8 + §11.2 override deltas)."""

    __tablename__ = "approvals"
    __table_args__ = (
        CheckConstraint(
            "approval_type IN ('credit_waiver', 'debit_note', 'bom_yield', "
            "'credit_rebaseline', 'confirmation_correction', 'issue_correction', "
            "'override_review')",
            name="approval_type",
        ),
        CheckConstraint(
            "status IN ('pending', 'approved', 'declined', 'hold', 'overridden')",
            name="status",
        ),
    )

    id: Mapped[intpk]
    approval_type: Mapped[str] = mapped_column(Text, nullable=False)
    ref_type: Mapped[str] = mapped_column(Text, nullable=False)
    ref_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    payload: Mapped[dict] = mapped_column(JSONVariant, nullable=False)
    required_roles: Mapped[list] = mapped_column(ArrayVariant, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[created_at]
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # §11.2 emergency override deltas.
    overridden_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    override_reason: Mapped[str | None] = mapped_column(Text)


class ApprovalDecision(Base):
    """One decision row per required role on an approval (§4.8 + §11.2 delegation delta)."""

    __tablename__ = "approval_decisions"
    __table_args__ = (
        CheckConstraint("decision IN ('approve', 'decline', 'hold')", name="decision"),
    )

    id: Mapped[intpk]
    approval_id: Mapped[int] = mapped_column(ForeignKey("approvals.id"), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    decision: Mapped[str] = mapped_column(Text, nullable=False)
    note: Mapped[str | None] = mapped_column(Text)
    decided_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    on_behalf_of_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))


class ApprovalDelegation(Base):
    """Delegation of approval authority within a validity window (§11.2)."""

    __tablename__ = "approval_delegations"

    id: Mapped[intpk]
    principal_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    delegate_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    approval_type: Mapped[str | None] = mapped_column(Text)  # NULL = all types
    valid_from: Mapped[date] = mapped_column(Date, nullable=False)
    valid_to: Mapped[date] = mapped_column(Date, nullable=False)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))


class Anomaly(Base):
    """Rule-engine anomaly flag, hard or soft (§4.8)."""

    __tablename__ = "anomalies"
    __table_args__ = (
        CheckConstraint("severity IN ('hard', 'soft')", name="severity"),
        CheckConstraint("status IN ('open', 'in_review', 'resolved')", name="status"),
    )

    id: Mapped[intpk]
    rule_code: Mapped[str] = mapped_column(Text, nullable=False)
    severity: Mapped[str] = mapped_column(Text, nullable=False)
    ref_type: Mapped[str] = mapped_column(Text, nullable=False)
    ref_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    observed: Mapped[dict | None] = mapped_column(JSONVariant)
    expected: Mapped[dict | None] = mapped_column(JSONVariant)
    message_en: Mapped[str] = mapped_column(Text, nullable=False)
    message_mr: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    resolved_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[created_at]


class Notification(Base):
    """User notification, blocker or digest tier (§4.8 + §11.14 deltas)."""

    __tablename__ = "notifications"
    __table_args__ = (
        CheckConstraint("tier IN ('blocker', 'digest')", name="tier"),
        Index(
            "ix_notifications_user_id_unread",
            "user_id",
            postgresql_where=text("read_at IS NULL"),
            sqlite_where=text("read_at IS NULL"),
        ),
    )

    id: Mapped[intpk]
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    body: Mapped[str | None] = mapped_column(Text)
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    ref_type: Mapped[str | None] = mapped_column(Text)
    ref_id: Mapped[int | None] = mapped_column(BigInteger)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[created_at]
    # §11.14 deltas.
    tier: Mapped[str] = mapped_column(Text, nullable=False, server_default=text("'digest'"))
    acted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    next_repeat_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    digest_of: Mapped[dict | None] = mapped_column(JSONVariant)  # source notification ids


class EscalationRule(Base):
    """Configurable escalation timer rule; predicate lives in code (§11.8)."""

    __tablename__ = "escalation_rules"

    id: Mapped[intpk]
    rule_code: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    ref_type: Mapped[str] = mapped_column(Text, nullable=False)
    threshold_min: Mapped[int] = mapped_column(Integer, nullable=False)
    notify_chain: Mapped[dict] = mapped_column(JSONVariant, nullable=False)  # [{after_min, roles[]}]
    repeat_min: Mapped[int | None] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))


class EscalationEvent(Base):
    """Fired escalation stage for a qualifying ref (§11.8)."""

    __tablename__ = "escalation_events"
    __table_args__ = (UniqueConstraint("rule_code", "ref_id", "stage"),)

    id: Mapped[intpk]
    rule_code: Mapped[str] = mapped_column(Text, nullable=False)
    ref_type: Mapped[str] = mapped_column(Text, nullable=False)
    ref_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    stage: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    notified_roles: Mapped[list] = mapped_column(ArrayVariant, nullable=False)
    created_at: Mapped[created_at]
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
