from fastapi import APIRouter
import os
from engine.arbitrage_v2 import ENGINE_VERSION

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


@router.get("/debug/jwt")
def debug_jwt():
    s = os.getenv("JWT_SECRET", "")
    a = os.getenv("JWT_ALGO", "HS256")
    return {
        "has_jwt_secret": bool(s),
        "jwt_secret_len": len(s),
        "jwt_algo": a,
    }
