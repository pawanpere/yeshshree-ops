"""Identity & access models. Spec: Architecture §4.1 (+§11.15 vendor credential reset)."""
from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, created_at, intpk


class User(Base):
    """One row per person. role gates routers; station picks home tiles. §4.1."""
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint("role IN ('admin','management','planning','plant_ops','supervisor','vendor')", name="role_valid"),
        CheckConstraint("station IS NULL OR station IN ('gate','qc','store','ppc')", name="station_valid"),
        CheckConstraint("language IN ('en','mr')", name="language_valid"),
    )
    id: Mapped[intpk]
    username: Mapped[str] = mapped_column(Text, unique=True)
    password_hash: Mapped[str] = mapped_column(Text)
    pin_hash: Mapped[str | None] = mapped_column(Text)
    full_name: Mapped[str] = mapped_column(Text)
    role: Mapped[str] = mapped_column(Text)
    station: Mapped[str | None] = mapped_column(Text)
    vendor_id: Mapped[int | None] = mapped_column(ForeignKey("vendors.id"))
    phone: Mapped[str | None] = mapped_column(Text)
    language: Mapped[str] = mapped_column(Text, default="en", server_default="en")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    created_at: Mapped[created_at]


class StationDevice(Base):
    """Registered station device (gate scanner kiosk etc.); keyed by device_key. §4.1."""
    __tablename__ = "station_devices"
    id: Mapped[intpk]
    device_key: Mapped[str] = mapped_column(Text, unique=True)
    station: Mapped[str] = mapped_column(Text)
    label: Mapped[str] = mapped_column(Text)
    registered_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")


class AuthSession(Base):
    """Refresh-token session per login; revoked on logout/credential reset. §4.1."""
    __tablename__ = "auth_sessions"
    id: Mapped[intpk]
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    refresh_token_hash: Mapped[str] = mapped_column(Text)
    device_key: Mapped[str | None] = mapped_column(Text)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[created_at]


class OtpCode(Base):
    """Mock OTP now, real SMS later — same table either way. §4.1."""
    __tablename__ = "otp_codes"
    id: Mapped[intpk]
    phone: Mapped[str] = mapped_column(Text)
    code: Mapped[str] = mapped_column(Text)
    purpose: Mapped[str] = mapped_column(Text)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
