"""TOTP (RFC 6238) helpers for 2FA — standard library only (no PyPI dependency)."""
import base64
import hashlib
import hmac
import secrets
import struct
import time
from typing import List


def generate_secret(length: int = 20) -> str:
    """Generate a random base32-encoded TOTP secret."""
    raw = secrets.token_bytes(length)
    return base64.b32encode(raw).decode("ascii").rstrip("=")


def _hotp(secret: bytes, counter: int, digits: int = 6) -> str:
    """HMAC-based OTP (RFC 4226)."""
    msg = struct.pack(">Q", counter)
    digest = hmac.new(secret, msg, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    truncated = (
        (digest[offset] & 0x7F) << 24
        | (digest[offset + 1] & 0xFF) << 16
        | (digest[offset + 2] & 0xFF) << 8
        | (digest[offset + 3] & 0xFF)
    )
    code = truncated % (10**digits)
    return f"{code:0{digits}d}"


def totp_now(secret_b32: str, timestep: int = 30, digits: int = 6) -> str:
    """Current TOTP code for the given base32 secret."""
    secret = base64.b32decode(secret_b32 + "=" * ((8 - len(secret_b32) % 8) % 8))
    counter = int(time.time()) // timestep
    return _hotp(secret, counter, digits)


def verify_totp(secret_b32: str, code: str, window: int = 1) -> bool:
    """Verify a TOTP code against the current time, with a tolerance window."""
    code = code.strip()
    if not code.isdigit() or len(code) != 6:
        return False
    for offset in range(-window, window + 1):
        counter = int(time.time()) // 30 + offset
        secret = base64.b32decode(secret_b32 + "=" * ((8 - len(secret_b32) % 8) % 8))
        if _hotp(secret, counter) == code:
            return True
    return False


def generate_backup_codes(count: int = 8, length: int = 8) -> List[str]:
    """Generate single-use backup codes."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return [
        "".join(secrets.choice(alphabet) for _ in range(length)) for _ in range(count)
    ]
