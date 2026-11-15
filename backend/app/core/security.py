"""Password hashing (bcrypt) and JWT access tokens (PyJWT)."""
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from .config import SECRET_KEY, TOKEN_TTL_DAYS
from .errors import UnauthorizedError

ALGORITHM = "HS256"


def hash_password(raw: str) -> str:
    return bcrypt.hashpw(raw.encode(), bcrypt.gensalt()).decode()


def verify_password(raw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(raw.encode(), hashed.encode())
    except ValueError:
        return False


def create_token(user_id: int, version: int = 0) -> str:
    payload = {
        "sub": str(user_id),
        "ver": version,
        "exp": datetime.now(timezone.utc) + timedelta(days=TOKEN_TTL_DAYS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> tuple[int, int]:
    """Return `(account id, token version)` or raise UnauthorizedError."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return int(payload["sub"]), int(payload.get("ver", 0))
    except (jwt.PyJWTError, KeyError, ValueError, TypeError) as e:
        raise UnauthorizedError("Invalid or expired token.") from e
