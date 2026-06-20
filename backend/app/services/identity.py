"""User + station-device admin CRUD (Phase 5). Admin-only; same rules as master data:
NO deletes (deactivate via is_active=false); every change writes a field-level audit
diff in the same transaction. Passwords/PINs are hashed here and never read back.
"""
from sqlalchemy.orm import Session

from app.core.audit import record
from app.core.deps import CurrentUser, _error
from app.core.security import hash_password
from app.models.identity import StationDevice, User
from app.services.master import apply_update, get_or_404

USER_EDITABLE = {"full_name", "role", "station", "vendor_id", "phone", "language",
                 "is_active"}
DEVICE_EDITABLE = {"label", "station", "is_active"}


def _unique_or_409(db: Session, model, field: str, value: str, label: str) -> None:
    if db.query(model).filter(getattr(model, field) == value).first() is not None:
        raise _error("ALREADY_EXISTS", f"A {label} with that {field} already exists",
                     "हे आधीच अस्तित्वात आहे", 409, {field: value})


# --- users ---
def create_user(db: Session, actor: CurrentUser, body) -> User:
    _unique_or_409(db, User, "username", body.username, "user")
    user = User(
        username=body.username, full_name=body.full_name, role=body.role,
        station=body.station, vendor_id=body.vendor_id, phone=body.phone,
        language=body.language, password_hash=hash_password(body.password),
        pin_hash=hash_password(body.pin) if body.pin else None,
    )
    db.add(user)
    db.flush()
    record(db, user_id=actor.id, entity="users", entity_id=user.id, action="create",
           before=None, after={"username": user.username, "role": user.role})
    db.commit()
    db.refresh(user)
    return user


def update_user(db: Session, actor: CurrentUser, user_id: int, changes: dict) -> User:
    user = get_or_404(db, User, user_id, "user")
    # Credentials are hashed + audited as a boolean (never the value).
    pwd = changes.pop("password", None)
    pin = changes.pop("pin", None)
    if pwd:
        user.password_hash = hash_password(pwd)
        record(db, user_id=actor.id, entity="users", entity_id=user.id,
               action="update", before=None, after={"password_changed": True})
    if pin is not None:
        user.pin_hash = hash_password(pin) if pin else None
        record(db, user_id=actor.id, entity="users", entity_id=user.id,
               action="update", before=None, after={"pin_changed": True})
    apply_update(db, user, {k: v for k, v in changes.items() if v is not None},
                 actor, "users", allowed=USER_EDITABLE)
    if pwd or pin is not None:
        db.commit()
    db.refresh(user)
    return user


# --- station devices ---
def create_device(db: Session, actor: CurrentUser, body) -> StationDevice:
    _unique_or_409(db, StationDevice, "device_key", body.device_key, "device")
    device = StationDevice(device_key=body.device_key, station=body.station,
                           label=body.label, registered_by=actor.id)
    db.add(device)
    db.flush()
    record(db, user_id=actor.id, entity="station_devices", entity_id=device.id,
           action="create", before=None, after={"device_key": device.device_key})
    db.commit()
    db.refresh(device)
    return device


def update_device(db: Session, actor: CurrentUser, device_id: int,
                  changes: dict) -> StationDevice:
    device = get_or_404(db, StationDevice, device_id, "station device")
    apply_update(db, device, {k: v for k, v in changes.items() if v is not None},
                 actor, "station_devices", allowed=DEVICE_EDITABLE)
    return device
