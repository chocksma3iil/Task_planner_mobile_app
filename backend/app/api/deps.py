"""FastAPI dependencies shared by the routers."""
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from ..core.database import get_db
from ..core.errors import UnauthorizedError
from ..core.security import decode_token
from ..models import Assignee

_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> Assignee:
    """Bearer-token auth dependency; raises 401 for missing/invalid tokens."""
    if credentials is None:
        raise UnauthorizedError("Not authenticated.")
    user = db.get(Assignee, decode_token(credentials.credentials))
    if user is None:
        raise UnauthorizedError("Unknown account.")
    return user


CurrentUser = Annotated[Assignee, Depends(get_current_user)]
DbSession = Annotated[Session, Depends(get_db)]
