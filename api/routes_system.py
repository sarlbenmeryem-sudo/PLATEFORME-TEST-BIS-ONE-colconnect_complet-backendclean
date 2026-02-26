from fastapi import APIRouter
import os

router = APIRouter(prefix="/api/v1", tags=["system"])


@router.get("/health")
def health():
    return {"ok": True}


@router.get("/version")
def version():
    return {
        "render_git_commit": os.getenv("RENDER_GIT_COMMIT", "unknown"),
        "api_version": "v1",
    }
