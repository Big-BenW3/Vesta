"""App factory: lifespan inits the DB, middleware guarantees the envelope."""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

from core.config import load
from models import store
from models.errors import envelope_middleware
from routers import agent_routes, reasoning_routes, vault_routes


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Boot: fail fast on missing secrets, init SQLite, then serve."""
    settings = load()  # why: crash on boot without secrets, not on first request
    store.init_db(settings.sqlite_path)
    app.state.settings = settings
    yield


def create_app() -> FastAPI:
    """Assemble v1 API + health + verifier page."""
    settings = load()
    app = FastAPI(title="Vesta API", version="1.0.0", redirect_slashes=True)
    app.middleware("http")(envelope_middleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["X-API-Key", "Content-Type"],
        max_age=600,
    )

    @app.middleware("http")
    async def security_headers(request, call_next):
        resp = await call_next(request)
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        return resp

    app.include_router(vault_routes.router, prefix="/api/v1")
    app.include_router(reasoning_routes.router, prefix="/api/v1")
    app.include_router(agent_routes.router, prefix="/api/v1")

    @app.get("/healthz")
    def healthz() -> dict:
        return {"ok": True}

    @app.get("/verifier")
    def verifier() -> FileResponse:
        return FileResponse("static/verifier.html", media_type="text/html")

    return app


app = create_app()
