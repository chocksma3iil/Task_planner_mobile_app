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


def create_token(user_id: int, token_version: int = 0) -> str:
    """Sign a token carrying the account id and its current session version."""
    payload = {
        "sub": str(user_id),
        "ver": token_version,
        "exp": datetime.now(timezone.utc) + timedelta(days=TOKEN_TTL_DAYS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> tuple[int, int]:
    """Return `(account id, token version)` in [token], or raise 401.

    Tokens issued before token versioning carry no `ver` claim; they decode as
    version 0, which matches every account until its first password reset.
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return int(payload["sub"]), int(payload.get("ver", 0))
    except (jwt.PyJWTError, KeyError, TypeError, ValueError) as e:
        raise UnauthorizedError("Invalid or expired token.") from e
