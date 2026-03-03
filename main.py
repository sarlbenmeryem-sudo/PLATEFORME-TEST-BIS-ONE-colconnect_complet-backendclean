from fastapi import FastAPI

from api.routes_system import router as system_router, legacy_root, legacy_api
from api.routes_arbitrage import router as arbitrage_router
from database.mongo import ensure_indexes

app = FastAPI(title="ColConnect API", version="1.0.0", docs_url="/api/docs", openapi_url="/api/openapi.json", redoc_url=None)


@app.on_event("startup")
def startup_event():
    try:
        ensure_indexes()
    except Exception:
        # Ne jamais bloquer le démarrage pour une histoire d'index
        pass


app.include_router(system_router)
app.include_router(legacy_root)
app.include_router(legacy_api)
app.include_router(arbitrage_router)


@app.get("/health", include_in_schema=False)
def health():
    return {"ok": True}

@app.get("/api/health", include_in_schema=False)
def api_health_alias():
    return {"ok": True}

# ---- CC: /api/deploy (truth on what is running) ----
from pathlib import Path
from fastapi import Response

def _read_deploy_sha() -> str:
    p = Path(__file__).with_name("DEPLOY_SHA")
    if p.exists():
        s = p.read_text(encoding="utf-8").strip()
        if s:
            return s
    return "unknown"

@app.get("/api/deploy")
def api_deploy():
    return {"deploy_sha": _read_deploy_sha()}



@app.get("/api/v1/deploy")
def api_v1_deploy():
    return api_deploy()
# ---- CC deploy-sha helpers + /api/deploy ----
import os
from pathlib import Path
from datetime import datetime, timezone

def _cc_read_deploy_sha() -> str:
    # Priority: env var > DEPLOY_SHA file > unknown
    env_sha = os.getenv("DEPLOY_SHA") or os.getenv("GIT_SHA") or os.getenv("RENDER_GIT_COMMIT")
    if env_sha and env_sha.strip():
        return env_sha.strip()
    p = Path(__file__).with_name("DEPLOY_SHA")
    if p.exists():
        s = p.read_text(encoding="utf-8").strip()
        if s:
            return s
    return "unknown"

@app.get("/api/deploy")
def cc_api_deploy():
    return {
        "deploy_sha": _cc_read_deploy_sha(),
        "time_utc": datetime.now(timezone.utc).isoformat(),
    }
