"""Application errors and their HTTP representation.

Routers/services raise these; `main` registers one handler that serializes
`detail` exactly as the Flutter client expects:
  * plain string for auth/permission/business errors (client: StateError),
  * `{"code", "message"}` for assignment/project-choice errors
    (client: ArgumentError).
"""
from typing import Any


class ApiError(Exception):
    """Base application error with an HTTP status and optional client code."""

    status_code = 400
    code: str | None = None

    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        code: str | None = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        if status_code is not None:
            self.status_code = status_code
        if code is not None:
            self.code = code

    @property
    def detail(self) -> Any:
        if self.code is not None:
            return {"code": self.code, "message": self.message}
        return self.message


class RuleError(ApiError):
    """Business-rule violation."""


class AssignmentError(RuleError):
    """Assignment violation the client surfaces as an ArgumentError."""

    code = "invalid_assignment"


class ProjectRequiredError(RuleError):
    """A non-first sign-up must choose a project."""

    code = "project_required"

    def __init__(self) -> None:
        super().__init__("Choose a project to join.")


class NotFoundError(ApiError):
    status_code = 404


class ConflictError(ApiError):
    status_code = 409


class UnauthorizedError(ApiError):
    status_code = 401


class ForbiddenError(ApiError):
    status_code = 403


class PendingAccountError(ForbiddenError):
    """Account exists but the project owner has not confirmed it yet."""

    def __init__(self) -> None:
        super().__init__("Account is waiting for project owner confirmation.")
