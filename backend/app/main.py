"""FastAPI application: versioned API, CORS, error mapping, schema bootstrap."""
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from . import models  # noqa: F401 - registers tables on Base.metadata
from .api.router import api_router
from .core.config import CORS_ORIGINS, CREATE_SCHEMA_ON_STARTUP
from .core.database import Base, engine
from .core.errors import ApiError


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Development convenience only; production runs `alembic upgrade head`.
    if CREATE_SCHEMA_ON_STARTUP:
        Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title="Task Planner API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(ApiError)
async def api_error_handler(_: Request, exc: ApiError) -> JSONResponse:
    """Keep the client contract: plain-string or `{code, message}` detail."""
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail},
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(
    _: Request, exc: RequestValidationError
) -> JSONResponse:
    """Turn Pydantic's error list into one readable message."""
    errors = exc.errors()
    first = errors[0] if errors else {"msg": "Invalid request.", "loc": ()}
    location = ".".join(
        str(part) for part in first.get("loc", ()) if part != "body"
    )
    message = first.get("msg", "Invalid request.")
    detail = f"{location}: {message}" if location else message
    return JSONResponse(status_code=422, content={"detail": detail})


app.include_router(api_router)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok"}
