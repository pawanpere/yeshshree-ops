"""Auth dependencies. `require(*roles)` guards every router (CLAUDE.md invariant 5 note:
role gate lives here; VENDOR DATA SCOPING lives in services, from CurrentUser.vendor_id)."""
import datetime as dt
from dataclasses import dataclass

import jwt
from fastapi import Depends, HTTPException, Request

from app.core.security import decode_access_token


@dataclass(frozen=True)
class CurrentUser:
    id: int
    username: str
    role: str
    station: str | None
    vendor_id: int | None
    device_key: str | None


def _error(code: str, message_en: str, message_mr: str, status: int,
           details: dict | None = None) -> HTTPException:
    """Uniform error envelope (CLAUDE.md invariant 10)."""
    return HTTPException(status_code=status, detail={
        "code": code, "message_en": message_en, "message_mr": message_mr,
        "details": details or {},
    })


def get_current_user(request: Request) -> CurrentUser:
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise _error("AUTH_MISSING", "Login required", "लॉगिन आवश्यक आहे", 401,
                     {"server_time": dt.datetime.now(dt.timezone.utc).isoformat()})
    try:
        claims = decode_access_token(auth.removeprefix("Bearer "))
    except jwt.PyJWTError:
        # server_time lets the client detect device clock skew (§11.15)
        raise _error("AUTH_INVALID", "Session expired — log in again",
                     "सत्र संपले — पुन्हा लॉगिन करा", 401,
                     {"server_time": dt.datetime.now(dt.timezone.utc).isoformat()})
    user = CurrentUser(
        id=int(claims["sub"]), username=claims["username"], role=claims["role"],
        station=claims.get("station"), vendor_id=claims.get("vendor_id"),
        device_key=claims.get("device_key"),
    )
    request.state.user = user  # audit middleware reads this
    return user


def require(*roles: str):
    """Usage: Depends(require('admin', 'planning')). Empty roles = any authenticated."""
    def checker(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if roles and user.role not in roles:
            raise _error("FORBIDDEN", "You don't have access to this",
                         "तुम्हाला यासाठी प्रवेश नाही", 403, {"required": list(roles)})
        return user
    return checker
