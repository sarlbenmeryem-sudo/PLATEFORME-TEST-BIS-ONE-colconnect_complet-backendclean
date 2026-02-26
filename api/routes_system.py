from fastapi import APIRouter
import os

router_v1 = APIRouter(prefix="/api/v1", tags=["system"])
router_legacy = APIRouter(prefix="/api", tags=["legacy"])
router_root = APIRouter(tags=["legacy"])


@router_v1.get("/health")
def health_v1():
    return {"ok": True}


@router_v1.get("/version")
def version_v1():
    return {
        "render_git_commit": os.getenv("RENDER_GIT_COMMIT", "unknown"),
        "api_version": "v1",
    }


# ---- legacy aliases ----
@router_root.get("/health")
def health_root():
    return {"ok": True}


@router_legacy.get("/version")
def version_legacy():
    return {
        "render_git_commit": os.getenv("RENDER_GIT_COMMIT", "unknown"),
        "api_version": "v1",
    }
