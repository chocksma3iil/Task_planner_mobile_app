"""Comment edit/delete endpoints (author-only, soft delete)."""
from fastapi import APIRouter, Response

from ...schemas import CommentOut, CommentUpdate
from ...services import comments as comment_service
from ..deps import CurrentUser, DbSession

router = APIRouter(tags=["comments"])


@router.patch("/comments/{comment_id}", response_model=CommentOut)
def update_comment(
    comment_id: int,
    body: CommentUpdate,
    db: DbSession,
    user: CurrentUser,
):
    return comment_service.update_comment(
        db, actor=user, comment_id=comment_id, body=body.body
    )


@router.delete("/comments/{comment_id}", status_code=204)
def delete_comment(
    comment_id: int, db: DbSession, user: CurrentUser
) -> Response:
    comment_service.delete_comment(db, actor=user, comment_id=comment_id)
    return Response(status_code=204)
