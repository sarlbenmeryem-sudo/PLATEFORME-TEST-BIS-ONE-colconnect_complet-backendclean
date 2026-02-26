from fastapi import APIRouter
import os

from engine.arbitrage_v2 import ENGINE_VERSION

# v1 router
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


# legacy (root + /api) — optionnel mais utile
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

import hashlib

@router.get("/debug/jwt-hash")
def debug_jwt_hash():
    s = os.getenv("JWT_SECRET", "")
    s2 = s.strip()
    return {
        "len_raw": len(s),
        "len_stripped": len(s2),
        "sha256_stripped": hashlib.sha256(s2.encode("utf-8")).hexdigest(),
        "jwt_algo": os.getenv("JWT_ALGO", "HS256"),
    }
