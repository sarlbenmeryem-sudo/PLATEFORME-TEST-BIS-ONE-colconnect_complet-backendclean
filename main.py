from fastapi import FastAPI

from api.routes_system import router as system_v1_router
from api.routes_arbitrage import router as arbitrage_v1_router

app = FastAPI(title="ColConnect API", version="1.0.0")

# Routers v1 (source of truth)
app.include_router(system_v1_router)
app.include_router(arbitrage_v1_router)

# ---- Legacy aliases (/api/*) ----
# On remonte les mêmes routes sous /api en réécrivant le prefix.
# (FastAPI ne permet pas de "changer" le prefix d'un router existant, donc on crée des wrappers.)
from fastapi import APIRouter

legacy = APIRouter(prefix="/api", tags=["legacy"])

@legacy.get("/health")
def legacy_health():
    return {"ok": True}

@legacy.get("/version")
def legacy_version():
    # même payload que v1/version, mais sans dépendre d'un import circulaire
    import os
    return {"render_git_commit": os.getenv("RENDER_GIT_COMMIT", "unknown"), "api_version": "v1"}

app.include_router(legacy)
