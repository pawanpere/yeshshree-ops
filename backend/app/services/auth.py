"""Auth business logic (P04/P05). Spec: Architecture §5.1.
Routers stay thin; everything decidable lives here."""
import datetime as dt
import secrets

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.deps import _error
from app.core.security import (create_access_token, hash_refresh_token,
                               new_refresh_token, verify_password)
from app.models.identity import AuthSession, OtpCode, StationDevice, User


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _issue_tokens(db: Session, user: User, device_key: str | None) -> dict:
    plain, hashed = new_refresh_token()
    db.add(AuthSession(
        user_id=user.id, refresh_token_hash=hashed, device_key=device_key,
        expires_at=_now() + dt.timedelta(days=get_settings().jwt_refresh_days),
    ))
    db.commit()
    return {
        "access_token": create_access_token(
            user_id=user.id, username=user.username, role=user.role,
            station=user.station, vendor_id=user.vendor_id, device_key=device_key),
        "refresh_token": plain,
        "role": user.role, "station": user.station, "full_name": user.full_name,
        "language": user.language,
    }


def login(db: Session, username: str, password: str, device_key: str | None) -> dict:
    user = db.query(User).filter_by(username=username, is_active=True).one_or_none()
    if user is None or not verify_password(password, user.password_hash):
        raise _error("AUTH_BAD_CREDENTIALS", "Wrong username or password",
                     "चुकीचे वापरकर्तानाव किंवा पासवर्ड", 401)
    return _issue_tokens(db, user, device_key)


def refresh(db: Session, refresh_token: str) -> dict:
    """Rotation: the used token's session is revoked and a new one issued.
    A revoked-token reuse (theft signal) revokes ALL the user's sessions."""
    hashed = hash_refresh_token(refresh_token)
    sess = db.query(AuthSession).filter_by(refresh_token_hash=hashed).one_or_none()
    if sess is None:
        raise _error("AUTH_INVALID", "Session expired — log in again",
                     "सत्र संपले — पुन्हा लॉगिन करा", 401)
    now = _now()
    expires = sess.expires_at if sess.expires_at.tzinfo else sess.expires_at.replace(tzinfo=dt.timezone.utc)
    if sess.revoked_at is not None:
        db.query(AuthSession).filter_by(user_id=sess.user_id, revoked_at=None).update(
            {"revoked_at": now})
        db.commit()
        raise _error("AUTH_REUSE", "Security check failed — log in again",
                     "सुरक्षा तपासणी अयशस्वी — पुन्हा लॉगिन करा", 401)
    if expires < now:
        raise _error("AUTH_INVALID", "Session expired — log in again",
                     "सत्र संपले — पुन्हा लॉगिन करा", 401)
    sess.revoked_at = now
    user = db.get(User, sess.user_id)
    if user is None or not user.is_active:
        raise _error("AUTH_INVALID", "Account disabled", "खाते निष्क्रिय", 401)
    return _issue_tokens(db, user, sess.device_key)


def logout(db: Session, refresh_token: str) -> None:
    sess = db.query(AuthSession).filter_by(
        refresh_token_hash=hash_refresh_token(refresh_token)).one_or_none()
    if sess is not None and sess.revoked_at is None:
        sess.revoked_at = _now()
        db.commit()


def pin_switch(db: Session, device_key: str, username: str, pin: str) -> dict:
    """Fast user switch on a REGISTERED station device only; user's station must
    match the device's station (Architecture §5.1)."""
    device = db.query(StationDevice).filter_by(device_key=device_key, is_active=True).one_or_none()
    if device is None:
        raise _error("DEVICE_UNKNOWN", "This device is not registered for PIN login",
                     "हे उपकरण PIN लॉगिनसाठी नोंदणीकृत नाही", 403)
    user = db.query(User).filter_by(username=username, is_active=True).one_or_none()
    if user is None or not user.pin_hash or not verify_password(pin, user.pin_hash):
        raise _error("AUTH_BAD_PIN", "Wrong PIN", "चुकीचा PIN", 401)
    if user.station != device.station:
        raise _error("STATION_MISMATCH", "Your station doesn't match this device",
                     "तुमचे स्टेशन या उपकरणाशी जुळत नाही", 403)
    device.last_seen_at = _now()
    return _issue_tokens(db, user, device_key)


def vendor_otp_request(db: Session, phone: str) -> dict:
    """MOCK OTP (plan decision 7): code persisted + returned as dev_code so demos work
    without SMS. Real SMS provider swaps in behind this same function — API unchanged."""
    user = db.query(User).filter_by(phone=phone, role="vendor", is_active=True).one_or_none()
    if user is None:
        raise _error("VENDOR_UNKNOWN", "No vendor account for this phone number",
                     "या फोन नंबरसाठी विक्रेता खाते नाही", 404)
    code = f"{secrets.randbelow(1_000_000):06d}"
    db.add(OtpCode(phone=phone, code=code, purpose="vendor_login",
                   expires_at=_now() + dt.timedelta(minutes=10)))
    db.commit()
    return {"sent": True, "dev_code": code}  # dev_code removed when real SMS lands


def vendor_otp_verify(db: Session, phone: str, code: str) -> dict:
    otp = (db.query(OtpCode)
           .filter_by(phone=phone, code=code, purpose="vendor_login", used_at=None)
           .order_by(OtpCode.id.desc()).first())
    now = _now()
    if otp is None or (otp.expires_at.tzinfo and otp.expires_at < now) or \
       (not otp.expires_at.tzinfo and otp.expires_at.replace(tzinfo=dt.timezone.utc) < now):
        raise _error("OTP_INVALID", "Wrong or expired code", "चुकीचा किंवा कालबाह्य कोड", 401)
    otp.used_at = now
    user = db.query(User).filter_by(phone=phone, role="vendor", is_active=True).one()
    return _issue_tokens(db, user, None)
