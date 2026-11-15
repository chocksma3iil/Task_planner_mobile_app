"""Feature routers under the versioned API prefix."""
from fastapi import APIRouter

from .routers import (
    ai,
    analytics,
    audit,
    auth,
    comments,
    members,
    notifications,
    projects,
    subtasks,
    tasks,
)

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(ai.router)
api_router.include_router(analytics.router)
api_router.include_router(audit.router)
api_router.include_router(auth.router)
api_router.include_router(comments.router)
api_router.include_router(projects.router)
api_router.include_router(members.router)
api_router.include_router(tasks.router)
api_router.include_router(notifications.router)
api_router.include_router(subtasks.router)
