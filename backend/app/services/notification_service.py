"""In-app notifications + email delivery for task/member actions.

Each action creates a `Notification` row (so the mobile client can list them)
and, when the recipient has opted in, sends an email via `email_service`.
"""
from typing import Any

from sqlalchemy.orm import Session

from ..core.config import SMTP_HOST
from ..core.time import utc_now
from ..models import Assignee, Notification, Task
from . import email_service


def _notify(
    db: Session,
    *,
    user: Assignee,
    n_type: str,
    title: str,
    body: str | None = None,
    payload: str | None = None,
    send_email: bool = True,
) -> None:
    """Persist an in-app notification and optionally email the recipient."""
    db.add(
        Notification(
            user_id=user.id,
            type=n_type,
            title=title,
            body=body,
            payload=payload,
        )
    )
    db.flush()
    if send_email and email_service.is_configured() and user.email:
        email_service.send_async(
            to=user.email,
            subject=title,
            body=body or title,
        )


def notify_comment_created(
    db: Session,
    *,
    task: Task,
    actor: Assignee,
    project_name: str,
    target_ids: set[int],
) -> None:
    """A comment was created; notify its assignee and mentions (once each)."""
    for target_id in target_ids:
        target = db.get(Assignee, target_id)
        if target is None or target.id == actor.id:
            continue
        _notify(
            db,
            user=target,
            n_type="comment_mention",
            title=f"New comment on task: {task.title}",
            body=(
                f"{actor.name} commented on '{task.title}' in project "
                f"'{project_name}'."
            ),
            payload=str(task.id),
        )


def notify_task_created(
    db: Session,
    *,
    task: Task,
    actor: Assignee,
    project_name: str,
    assignee: Assignee | None,
) -> None:
    """A task was created; notify its assignee (if any) and project members."""
    if assignee is not None and assignee.id != actor.id:
        _notify(
            db,
            user=assignee,
            n_type="task_created",
            title=f"New task assigned: {task.title}",
            body=(
                f"{actor.name} assigned you to '{task.title}' in project "
                f"'{project_name}'."
            ),
            payload=str(task.id),
        )

    # Email the whole project is out of scope for v1; only the assignee gets
    # a direct notification. Project-wide digest is deferred.


def notify_task_assigned(
    db: Session,
    *,
    task: Task,
    actor: Assignee,
    project_name: str,
    assignee: Assignee,
    previous_assignee_id: int | None,
) -> None:
    """A task's assignee changed; notify the new assignee."""
    if assignee.id == actor.id:
        return
    _notify(
        db,
        user=assignee,
        n_type="task_assigned",
        title=f"Task assigned to you: {task.title}",
        body=(
            f"{actor.name} assigned '{task.title}' to you in project "
            f"'{project_name}'."
        ),
        payload=str(task.id),
    )


def notify_task_completed(
    db: Session,
    *,
    task: Task,
    actor: Assignee,
    project_name: str,
    assignee: Assignee | None,
) -> None:
    """A task was completed; notify its assignee (if any)."""
    if assignee is None or assignee.id == actor.id:
        return
    _notify(
        db,
        user=assignee,
        n_type="task_completed",
        title=f"Task completed: {task.title}",
        body=(
            f"{actor.name} marked '{task.title}' as completed in project "
            f"'{project_name}'."
        ),
        payload=str(task.id),
    )


def notify_task_reopened(
    db: Session,
    *,
    task: Task,
    actor: Assignee,
    project_name: str,
    assignee: Assignee | None,
) -> None:
    """A completed task was reopened; notify its assignee (if any)."""
    if assignee is None or assignee.id == actor.id:
        return
    _notify(
        db,
        user=assignee,
        n_type="task_reopened",
        title=f"Task reopened: {task.title}",
        body=(
            f"{actor.name} reopened '{task.title}' in project "
            f"'{project_name}'."
        ),
        payload=str(task.id),
    )


def notify_task_deleted(
    db: Session,
    *,
    task_title: str,
    actor: Assignee,
    project_name: str,
    assignee_id: int | None,
) -> None:
    """A task was deleted; notify its former assignee (if any)."""
    if assignee_id is None:
        return
    target = db.get(Assignee, assignee_id)
    if target is None or target.id == actor.id:
        return
    _notify(
        db,
        user=target,
        n_type="task_deleted",
        title=f"Task deleted: {task_title}",
        body=(
            f"{actor.name} deleted '{task_title}' from project "
            f"'{project_name}'."
        ),
    )


def notify_member_added(
    db: Session,
    *,
    member: Assignee,
    actor: Assignee,
    project_name: str,
) -> None:
    """A new member was added to a project; notify them."""
    if member.id == actor.id:
        return
    _notify(
        db,
        user=member,
        n_type="member_added",
        title=f"Added to project: {project_name}",
        body=(
            f"{actor.name} added you to project '{project_name}'."
        ),
    )


def notify_member_confirmed(
    db: Session,
    *,
    member: Assignee,
    actor: Assignee,
    project_name: str,
) -> None:
    """A pending member was confirmed; notify them."""
    if member.id == actor.id:
        return
    _notify(
        db,
        user=member,
        n_type="member_confirmed",
        title=f"Membership confirmed: {project_name}",
        body=(
            f"{actor.name} confirmed your membership in project "
            f"'{project_name}'. You can now log in."
        ),
    )


def notify_member_role_changed(
    db: Session,
    *,
    member: Assignee,
    actor: Assignee,
    project_name: str,
    new_role: str,
) -> None:
    """A member's role changed; notify them."""
    if member.id == actor.id:
        return
    _notify(
        db,
        user=member,
        n_type="member_role_changed",
        title=f"Role changed: {new_role}",
        body=(
            f"{actor.name} changed your role to '{new_role}' in project "
            f"'{project_name}'."
        ),
    )
