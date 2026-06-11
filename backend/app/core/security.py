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
