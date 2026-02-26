from fastapi import FastAPI

from api.routes_system import router_v1 as system_v1_router
from api.routes_system import router_legacy as system_legacy_router
from api.routes_system import router_root as system_root_router
from api.routes_arbitrage import router as arbitrage_router

app = FastAPI(title="ColConnect API", version="1.0.0")

app.include_router(system_v1_router)
app.include_router(system_legacy_router)
app.include_router(system_root_router)
app.include_router(arbitrage_router)
