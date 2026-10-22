"""Project request/response shapes."""
from pydantic import BaseModel, ConfigDict

from .common import OptionalText, RequiredText, UtcDateTime


class ProjectOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    description: str | None = None
    status: str
    owner_id: int | None = None
    created_at: UtcDateTime


class ProjectIn(BaseModel):
    name: RequiredText
    description: OptionalText = None


class AssignOwnerIn(BaseModel):
    owner_id: int
