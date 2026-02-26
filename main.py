from fastapi import FastAPI

from api.routes_system import router as system_router
from api.routes_arbitrage import router as arbitrage_router
from database.mongo import ensure_indexes

app = FastAPI(title="ColConnect API", version="1.0.0")

try:
    ensure_indexes()
except Exception:
    pass

app.include_router(system_router)
app.include_router(arbitrage_router)
