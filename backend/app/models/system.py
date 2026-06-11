"""System models (audit, SAP outbox/export, imports, station status).
Spec: Architecture §4.8 (+§11.1, §11.4 deltas)."""
from datetime import date, datetime
from decimal import Decimal
import uuid

from sqlalchemy import (BigInteger, Boolean, CheckConstraint, Date, DateTime, ForeignKey,
                        Index, Integer, SmallInteger, Text, UniqueConstraint, Uuid, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import ArrayVariant, Base, JSONVariant, Money, Qty, created_at, intpk


class AuditLog(Base):
    """Append-only request audit trail; DB role gets INSERT only (§4.8)."""

    __tablename__ = "audit_log"
    __table_args__ = (
        CheckConstraint(
            "action IN ('create', 'update', 'status_change', 'decision', 'login', 'export')",
            name="action",
        ),
        Index("ix_audit_log_entity", "entity", "entity_id"),
    )

    id: Mapped[intpk]
    at: Mapped[created_at]
    request_id: Mapped[str | None] = mapped_column(Text)
    user_id: Mapped[int | None] = mapped_column(BigInteger)  # no FK — log survives anything
    role: Mapped[str | None] = mapped_column(Text)
    station: Mapped[str | None] = mapped_column(Text)
    device_key: Mapped[str | None] = mapped_column(Text)
    # NULL for service-level field-change records (no HTTP context — audit.record())
    method: Mapped[str | None] = mapped_column(Text)
    path: Mapped[str | None] = mapped_column(Text)
    entity: Mapped[str | None] = mapped_column(Text)
    entity_id: Mapped[int | None] = mapped_column(BigInteger)
    action: Mapped[str] = mapped_column(Text, nullable=False)
    before: Mapped[dict | None] = mapped_column(JSONVariant)
    after: Mapped[dict | None] = mapped_column(JSONVariant)


class SapExportBatch(Base):
    """One generated SAP export file (§4.8)."""

    __tablename__ = "sap_export_batches"
    __table_args__ = (
        CheckConstraint(
            "status IN ('building', 'uploaded', 'verified', 'acked', 'failed')",
            name="status",
        ),
    )

    id: Mapped[intpk]
    seq_no: Mapped[int] = mapped_column(Integer, unique=True, nullable=False)
    record_type: Mapped[str] = mapped_column(Text, nullable=False)
    filename: Mapped[str] = mapped_column(Text, nullable=False)
    row_count: Mapped[int] = mapped_column(Integer, nullable=False)
    checksum: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[created_at]
    uploaded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SapOutbox(Base):
    """Outbox row per SAP-bound record, payload frozen at write time (§4.8)."""

    __tablename__ = "sap_outbox"
    __table_args__ = (
        CheckConstraint(
            "record_type IN ('GR', 'CONFIRMATION', 'ISSUE', 'DISPATCH', 'INVOICE')",
            name="record_type",
        ),
        CheckConstraint(
            "status IN ('pending', 'batched', 'sent', 'acked', 'failed')", name="status"
        ),
        Index("ix_sap_outbox_status", "status"),
    )

    id: Mapped[intpk]
    record_type: Mapped[str] = mapped_column(Text, nullable=False)
    record_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    payload: Mapped[dict] = mapped_column(JSONVariant, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    batch_id: Mapped[int | None] = mapped_column(ForeignKey("sap_export_batches.id"))
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))
    last_error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[created_at]
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ImportJob(Base):
    """Master/schedule/stock import job with row-level results (§4.8 + §11.1 sap_stock kind)."""

    __tablename__ = "import_jobs"
    __table_args__ = (
        CheckConstraint(
            "kind IN ('materials', 'boms', 'vendors', 'pos', 'schedule', 'sap_stock')",
            name="kind",
        ),
    )

    id: Mapped[intpk]
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    file_id: Mapped[int] = mapped_column(ForeignKey("files.id"), nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    rows_total: Mapped[int | None] = mapped_column(Integer)
    rows_ok: Mapped[int | None] = mapped_column(Integer)
    rows_failed: Mapped[int | None] = mapped_column(Integer)
    errors: Mapped[dict | None] = mapped_column(JSONVariant)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[created_at]


class StationStatus(Base):
    """Latest heartbeat per gate agent / station app device (§11.4)."""

    __tablename__ = "station_status"
    __table_args__ = (
        CheckConstraint("kind IN ('gate_agent', 'station_app')", name="kind"),
    )

    id: Mapped[intpk]
    device_key: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    last_heartbeat_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    agent_version: Mapped[str | None] = mapped_column(Text)
    detail: Mapped[dict | None] = mapped_column(JSONVariant)
