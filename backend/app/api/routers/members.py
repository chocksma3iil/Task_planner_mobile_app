"""Member endpoints: creation, owner confirmation, admin role changes."""
from fastapi import APIRouter, Query

from ...models import Assignee
from ...schemas import AccountListOut, AccountOut, MemberIn, RoleIn, TransferMemberIn
from ...services import members as member_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/members", tags=["members"])


@router.get("", response_model=AccountListOut)
def list_members(
    db: DbSession,
    user: CurrentUser,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> AccountListOut:
    items, total = member_service.list_members(db, actor=user, limit=limit, offset=offset)
    return AccountListOut(items=items, total=total, limit=limit, offset=offset)


@router.post("", response_model=AccountOut, status_code=201)
def create_member(
    body: MemberIn, db: DbSession, user: CurrentUser
) -> Assignee:
    return member_service.create_member(
        db,
        actor=user,
        name=body.name,
        email=body.email,
        password=body.password,
        position=body.position,
        project_id=body.project_id,
        role=body.role,
    )


@router.post("/{user_id}/confirm", response_model=AccountOut)
def confirm_member(
    user_id: int, db: DbSession, user: CurrentUser
) -> Assignee:
    return member_service.confirm_member(db, actor=user, user_id=user_id)


@router.post("/{user_id}/role", response_model=AccountOut)
def change_role(
    user_id: int, body: RoleIn, db: DbSession, user: CurrentUser
) -> Assignee:
    return member_service.change_role(
        db, actor=user, user_id=user_id, role=body.role
    )


@router.patch("/{user_id}/leave", response_model=AccountOut)
def leave_project(
    user_id: int, db: DbSession, user: CurrentUser
) -> Assignee:
    """A member leaves their own project (or is removed by an admin/owner)."""
    return member_service.leave_project(db, actor=user, user_id=user_id)


@router.patch("/{user_id}/transfer", response_model=AccountOut)
def transfer_member(
    user_id: int, body: TransferMemberIn, db: DbSession, user: CurrentUser
) -> Assignee:
    """Move a member to another project (admin or owner only)."""
    return member_service.transfer_member(
        db, actor=user, user_id=user_id, project_id=body.project_id
    )
