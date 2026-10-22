"""Sign-up (with first-account admin bootstrap), login, and session lookup."""
from fastapi import APIRouter

from ...models import Assignee
from ...schemas import AccountOut, LoginIn, LoginOut, SignUpIn
from ...services import auth as auth_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=AccountOut, status_code=201)
def sign_up(body: SignUpIn, db: DbSession) -> Assignee:
    return auth_service.sign_up(
        db,
        name=body.name,
        email=body.email,
        password=body.password,
        position=body.position,
        project_id=body.project_id,
    )


@router.post("/login", response_model=LoginOut)
def login(body: LoginIn, db: DbSession) -> LoginOut:
    account, token = auth_service.login(
        db, email=body.email, password=body.password
    )
    return LoginOut(access_token=token, account=account)


@router.get("/me", response_model=AccountOut)
def me(user: CurrentUser) -> Assignee:
    return user
