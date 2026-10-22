"""Feature routers under the versioned API prefix."""
from fastapi import APIRouter

from .routers import auth, members, projects, tasks

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(projects.router)
api_router.include_router(members.router)
api_router.include_router(tasks.router)
