"""Password/PIN hashing — stdlib pbkdf2 (no extra deps). P04 (auth) builds on this.
Format: pbkdf2$<iterations>$<salt_hex>$<hash_hex>"""
import hashlib
import os

_ITERATIONS = 200_000


def hash_password(plain: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", plain.encode(), salt, _ITERATIONS)
    return f"pbkdf2${_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(plain: str, stored: str) -> bool:
    try:
        _, iterations, salt_hex, hash_hex = stored.split("$")
        digest = hashlib.pbkdf2_hmac(
            "sha256", plain.encode(), bytes.fromhex(salt_hex), int(iterations)
        )
        return digest.hex() == hash_hex
    except (ValueError, AttributeError):
        return False


# --- JWT access tokens (P04). Claims: sub(user id), username, role, station,
# vendor_id, device_key. Refresh tokens are OPAQUE (random, hashed in auth_sessions) —
# never JWTs, so a leaked DB row can't be replayed as a token. ---
import datetime as _dt
import secrets

import jwt as _jwt

from app.core.config import get_settings


def create_access_token(*, user_id: int, username: str, role: str,
                        station: str | None, vendor_id: int | None,
                        device_key: str | None = None) -> str:
    s = get_settings()
    now = _dt.datetime.now(_dt.timezone.utc)
    payload = {
        "sub": str(user_id), "username": username, "role": role, "station": station,
        "vendor_id": vendor_id, "device_key": device_key,
        "iat": now, "exp": now + _dt.timedelta(minutes=s.jwt_access_minutes),
    }
    return _jwt.encode(payload, s.jwt_secret, algorithm="HS256")


def decode_access_token(token: str) -> dict:
    """Raises jwt.PyJWTError on invalid/expired — callers map to the 401 envelope
    (which includes details.server_time for the clock-skew hint, §11.15)."""
    return _jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])


def new_refresh_token() -> tuple[str, str]:
    """Returns (plain_token, sha256_hash). Plain goes to the client once;
    only the hash is stored (auth_sessions.refresh_token_hash)."""
    plain = secrets.token_urlsafe(48)
    return plain, hashlib.sha256(plain.encode()).hexdigest()


def hash_refresh_token(plain: str) -> str:
    return hashlib.sha256(plain.encode()).hexdigest()
