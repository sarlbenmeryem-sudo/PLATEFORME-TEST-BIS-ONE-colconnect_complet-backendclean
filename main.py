from fastapi import FastAPI

def _cc_get_deploy_sha() -> str:
    """
    Runtime truth:
    1) DEPLOY_SHA from container ENV (baked at build time in Dockerfile)
    2) fallback to file (DEPLOY_SHA / DEPLOY_SHA.txt) if present
    3) fallback 'unknown'
    """
    v = os.getenv("DEPLOY_SHA", "").strip()
    if v:
        return v

    for p in ("/app/DEPLOY_SHA", "/app/DEPLOY_SHA.txt", "DEPLOY_SHA", "DEPLOY_SHA.txt"):
        try:
            with open(p, "r", encoding="utf-8") as f:
                w = f.read().strip()
                if w:
                    return w
        except Exception:
            pass

    return "unknown"
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

# ---- CC: DEPLOY_SHA (build arg) precedence for /api/deploy ----
def _cc_deploy_sha() -> str:
    v = os.getenv("DEPLOY_SHA")
    if v and v.strip():
        return v.strip()
    # fallback: keep existing helpers if present
    try:
        return _cc_read_deploy_sha()  # type: ignore[name-defined]
    except Exception:
        try:
            return _read_deploy_sha()  # type: ignore[name-defined]
        except Exception:
            return "unknown"


@app.get("/api/deploy")
def api_deploy():
    return {"deploy_sha": _cc_get_deploy_sha()}
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
    return {"deploy_sha": _cc_get_deploy_sha()}

# --- ColConnect deploy endpoints (ENV ONLY) ---
def _cc_deploy_env_only() -> str:
    v = os.getenv("DEPLOY_SHA", "").strip()
    return v if v else "unknown"

@app.get("/api/deploy")
def cc_deploy() -> dict:
    return {"deploy_sha": _cc_deploy_env_only()}

@app.get("/api/v1/deploy")
def cc_deploy_v1() -> dict:
    return {"deploy_sha": _cc_deploy_env_only()}
# --- End ColConnect deploy endpoints (ENV ONLY) ---




# CC_PATCH_SIM_API_LOCAL_V1
from typing import Any, Dict, Optional
from datetime import datetime
from fastapi import Body
from fastapi.middleware.cors import CORSMiddleware

try:
    if not getattr(app.state, "_cc_local_cors_v1", False):
        app.add_middleware(
            CORSMiddleware,
            allow_origins=[
                "http://127.0.0.1:8000",
                "http://localhost:8000",
                "http://127.0.0.1:8080",
                "http://localhost:8080",
            ],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        app.state._cc_local_cors_v1 = True
except Exception as e:
    print("[CC][SIM_LOCAL_V1] CORS middleware non ajouté:", e)

_CC_SIM_FIXTURES: Dict[str, Dict[str, Any]] = {
    "lyon": {
        "label": "Ville de Lyon",
        "ieb": 74,
        "iep": 69,
        "ics": 62,
        "delta_ism": -3,
        "volatilite": 31,
        "signaux_faibles": 2,
        "confidence": "moyenne",
        "weights": {"b": 0.42, "p": 0.33, "s": 0.25},
        "risks": [
            "Tension sur le phasage budgétaire",
            "Retards multi-lots sur projets structurants",
            "Charge d'exécution des services élevée",
        ],
    },
    "paris": {
        "label": "Ville de Paris",
        "ieb": 78,
        "iep": 73,
        "ics": 66,
        "delta_ism": -1,
        "volatilite": 27,
        "signaux_faibles": 2,
        "confidence": "moyenne",
        "weights": {"b": 0.40, "p": 0.35, "s": 0.25},
        "risks": [
            "Complexité d'exécution sur portefeuille dense",
            "Sensibilité calendrier",
            "Arbitrages inter-dépendants",
        ],
    },
    "marseille": {
        "label": "Ville de Marseille",
        "ieb": 64,
        "iep": 58,
        "ics": 54,
        "delta_ism": -6,
        "volatilite": 39,
        "signaux_faibles": 3,
        "confidence": "faible",
        "weights": {"b": 0.43, "p": 0.32, "s": 0.25},
        "risks": [
            "Volatilité d'exécution élevée",
            "Risque de dérive coût/délai",
            "Capacité de pilotage sous tension",
        ],
    },
}

def _cc_sim_norm(cid: Optional[str]) -> str:
    cid = (cid or "lyon").strip().lower()
    return cid if cid else "lyon"

def _cc_zone_ism(score: int) -> str:
    if score >= 75:
        return "favorable"
    if score >= 55:
        return "sous_controle"
    return "critique"

def _cc_zone_irm(score: int) -> str:
    if score < 30:
        return "faible"
    if score < 60:
        return "vigilance"
    return "eleve"

def _cc_projection_status(ism: int, irm: int, delta_ism: int) -> str:
    if irm >= 60 or delta_ism <= -5:
        return "Sous tension"
    if ism >= 75 and irm < 30:
        return "Stable"
    return "Vigilance"

def _cc_sim_payload(collectivite_id: Optional[str] = None) -> Dict[str, Any]:
    cid = _cc_sim_norm(collectivite_id)
    cfg = _CC_SIM_FIXTURES.get(cid, _CC_SIM_FIXTURES["lyon"])

    ieb = int(cfg["ieb"])
    iep = int(cfg["iep"])
    ics = int(cfg["ics"])

    w = cfg["weights"]
    ism = int(round((w["b"] * ieb) + (w["p"] * iep) + (w["s"] * ics)))

    delta_ism = int(cfg["delta_ism"])
    volatilite = int(cfg["volatilite"])
    signaux = int(cfg["signaux_faibles"])

    irm = int(round(max(0, min(100, (max(0, -delta_ism) * 4.0) + (volatilite * 0.55) + (signaux * 9.0)))))

    if delta_ism >= 2:
        trend = "Hausse"
    elif delta_ism <= -2:
        trend = "Baisse"
    else:
        trend = "Stable"

    projection_status = _cc_projection_status(ism, irm, delta_ism)

    return {
        "collectivite_id": cid,
        "collectivite_label": cfg["label"],
        "drivers": {
            "ieb": ieb,
            "iep": iep,
            "ics": ics,
        },
        "ism": {
            "score": ism,
            "trend": trend,
            "confidence": cfg["confidence"],
            "zone": _cc_zone_ism(ism),
        },
        "irm": {
            "score": irm,
            "zone": _cc_zone_irm(irm),
        },
        "projection": {
            "status": projection_status,
            "delta_ism": delta_ism,
            "volatilite": volatilite,
            "signaux_faibles": signaux,
            "horizon_days": 90,
        },
        "risks": {
            "top": cfg["risks"][:3],
        },
        "meta": {
            "source": "sim_local_v1_fixture",
            "generated_at": datetime.utcnow().isoformat() + "Z",
        },
    }

@app.get("/api/v1/sim/executive")
def cc_sim_executive_root():
    return _cc_sim_payload("lyon")

@app.get("/api/v1/sim/executive/{collectivite_id}")
def cc_sim_executive_by_id(collectivite_id: str):
    return _cc_sim_payload(collectivite_id)

@app.get("/api/v1/collectivites/{collectivite_id}/sim")
def cc_collectivite_sim(collectivite_id: str):
    return _cc_sim_payload(collectivite_id)

@app.get("/api/v1/collectivites/{collectivite_id}/sim/executive")
def cc_collectivite_sim_executive(collectivite_id: str):
    return _cc_sim_payload(collectivite_id)

@app.get("/api/v1/collectivites/{collectivite_id}/sim/projection")
def cc_collectivite_sim_projection(collectivite_id: str):
    payload = _cc_sim_payload(collectivite_id)
    return {
        "collectivite_id": payload["collectivite_id"],
        "collectivite_label": payload["collectivite_label"],
        "ism": payload["ism"],
        "irm": payload["irm"],
        "projection": payload["projection"],
        "meta": payload["meta"],
    }

@app.post("/api/v1/sim/run")
@app.post("/api/sim/run")
def cc_sim_run(body: Optional[Dict[str, Any]] = Body(default=None)):
    body = body or {}
    collectivite_id = body.get("collectivite_id", "lyon")
    return _cc_sim_payload(collectivite_id)
# END_CC_PATCH_SIM_API_LOCAL_V1

