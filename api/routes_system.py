from fastapi import APIRouter
import os

from engine.arbitrage_v2 import ENGINE_VERSION

# Router principal (v1)
router = APIRouter(prefix="/api/v1", tags=["system"])


@router.get("/health")
def health():
    return {"ok": True}


@router.get("/version")
def version():
    return {
        "render_git_commit": os.getenv("RENDER_GIT_COMMIT", "unknown"),
        "api_version": "v1",
        "engine_version": ENGINE_VERSION,
        "schema_version": "1.0.0",
    }


# --- Legacy minimal (optionnel) ---
legacy_root = APIRouter(tags=["legacy"])
legacy_api = APIRouter(prefix="/api", tags=["legacy"])


@legacy_root.get("/health")
def health_root():
    return {"ok": True}


@legacy_api.get("/version")
def version_legacy():
    return {
        "render_git_commit": os.getenv("RENDER_GIT_COMMIT", "unknown"),
        "api_version": "v1",
        "engine_version": ENGINE_VERSION,
        "schema_version": "1.0.0",
    }
