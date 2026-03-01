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
