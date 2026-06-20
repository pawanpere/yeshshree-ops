"""User + station-device admin schemas (Phase 5). Passwords/PINs are write-only:
never read back. Roles/stations/languages mirror the model CHECK vocabularies."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict

Role = Literal["admin", "management", "planning", "plant_ops", "supervisor", "vendor"]
Station = Literal["gate", "qc", "store", "ppc"]
Language = Literal["en", "mr"]


class _Read(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- users ---
class UserRead(_Read):
    id: int
    username: str
    full_name: str
    role: str
    station: str | None
    vendor_id: int | None
    phone: str | None
    language: str
    is_active: bool
    has_pin: bool = False  # derived; never the hash itself


class UserCreate(BaseModel):
    username: str
    full_name: str
    role: Role
    password: str
    pin: str | None = None
    station: Station | None = None
    vendor_id: int | None = None
    phone: str | None = None
    language: Language = "en"


class UserUpdate(BaseModel):
    # username is immutable; password/pin are re-hashed when present.
    full_name: str | None = None
    role: Role | None = None
    station: Station | None = None
    vendor_id: int | None = None
    phone: str | None = None
    language: Language | None = None
    is_active: bool | None = None
    password: str | None = None
    pin: str | None = None


# --- station devices ---
class StationDeviceRead(_Read):
    id: int
    device_key: str
    station: str
    label: str
    registered_by: int
    last_seen_at: datetime | None
    is_active: bool


class StationDeviceCreate(BaseModel):
    device_key: str
    station: Station
    label: str


class StationDeviceUpdate(BaseModel):
    # device_key is immutable (it's the device's identity on the floor).
    label: str | None = None
    station: Station | None = None
    is_active: bool | None = None
