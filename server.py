cat > server.new.py <<'PY'
from __future__ import annotations

import os
import uuid
from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

from bson import ObjectId
from fastapi import Body, FastAPI, HTTPException
from pydantic import BaseModel, Field
from pymongo import MongoClient
from pymongo.errors import PyMongoError

from engine.arbitrage_v2 import calculer_arbitrage_2_0

# -----------------------------
# CONFIG
# -----------------------------
MONGO_URI = os.getenv("MONGO_URI", "").strip()
DB_NAME = os.getenv("DB_NAME", "colconnect").strip()

app = FastAPI()

# -----------------------------
# VERSION ENDPOINT (debug deploy)
# -----------------------------
APP_GIT_COMMIT = os.getenv("RENDER_GIT_COMMIT", "unknown")


@app.get("/api/version")
def version():
    return {"render_git_commit": APP_GIT_COMMIT}


# -----------------------------
# ROOT + HEALTH (Render)
# Render peut envoyer HEAD /
# -----------------------------
@app.api_route("/", methods=["GET", "HEAD"])
def root():
    return {"status": "ok", "service": "plateforme-colconnect-api"}


@app.get("/health")
def health():
    return {"status": "ok"}


# -----------------------------
# MONGO (lazy init + safe)
# -----------------------------
mongo_client: Optional[MongoClient] = None


def get_db():
    """
    Retourne la DB Mongo si dispo, sinon lève une 500.
    On initialise le client à la demande (évite de crasher au boot).
    """
    global mongo_client
    if not MONGO_URI:
        raise HTTPException(status_code=500, detail="MongoDB non configuré (MONGO_URI manquante)")

    if mongo_client is None:
        try:
            mongo_client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        except PyMongoError as e:
            raise HTTPException(status_code=500, detail=f"MongoClient init failed: {e}")

    try:
        mongo_client.admin.command("ping")
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"MongoDB ping failed: {e}")

    return mongo_client[DB_NAME]


@app.on_event("shutdown")
def shutdown_event():
    global mongo_client
    if mongo_client is not None:
        mongo_client.close()
        mongo_client = None


# -----------------------------
# JSON SAFE (ObjectId + datetime + _id)
# -----------------------------
def _json_safe(x: Any) -> Any:
    if isinstance(x, ObjectId):
        return str(x)
    if isinstance(x, datetime):
        return x.isoformat()
    if isinstance(x, dict):
        return {k: _json_safe(v) for k, v in x.items() if k != "_id"}
    if isinstance(x, list):
        return [_json_safe(v) for v in x]
    return x


# -----------------------------
# Pydantic models (API contract) - INPUT
# -----------------------------
class ContraintesIn(BaseModel):
    budget_investissement_max: float = Field(..., gt=0)
    seuil_capacite_desendettement_ans: float = Field(..., gt=0)


class HypothesesIn(BaseModel):
    taux_subventions_moyen: float = Field(..., ge=0, le=1)
    inflation_travaux: float = Field(..., ge=0)
    annee_reference: int = Field(..., ge=2000, le=2100)
    epargne_brute_annuelle: float = Field(..., gt=0)
    encours_dette_initial: float = Field(..., ge=0)


class ProjetIn(BaseModel):
    id: str
    nom: str
    cout_ttc: float = Field(..., gt=0)
    priorite: Literal["elevee", "moyenne", "faible"] = "moyenne"
    impact_climat: Literal["fort", "moyen", "faible"] = "faible"
    impact_education: Literal["fort", "moyen", "faible"] = "faible"
    annee_realisation: int


class ArbitrageRunIn(BaseModel):
    mandat: str
    contraintes: ContraintesIn
    hypotheses: HypothesesIn
    projets: List[ProjetIn]


# -----------------------------
# TEST MONGO
# -----------------------------
@app.get("/api/test-mongo")
def test_mongo():
    if not MONGO_URI:
        return {"status": "error", "mongo": "not_configured"}

    try:
        db = get_db()
        return {"status": "ok", "mongo": "connected", "db": db.name}
    except HTTPException as e:
        return {"status": "error", "mongo": "connection_failed", "detail": e.detail}


# -----------------------------
# PROJETS - IMPORT
# -----------------------------
@app.post("/api/collectivites/{collectivite_id}/projets:import")
def import_projets(collectivite_id: str, projets: List[Dict[str, Any]] = Body(...)):
    db = get_db()

    db.projets.delete_many({"collectivite_id": collectivite_id})

    if projets:
        for p in projets:
            p["collectivite_id"] = collectivite_id
        db.projets.insert_many(projets)

    return {"status": "ok", "count": len(projets)}


# -----------------------------
# PROJETS - LISTE
# -----------------------------
@app.get("/api/collectivites/{collectivite_id}/projets")
def get_projets(collectivite_id: str):
    db = get_db()
    projets = list(db.projets.find({"collectivite_id": collectivite_id}, {"_id": 0}))
    return _json_safe(projets)


# -----------------------------
# ARBITRAGE - RUN (création + stockage)
# -----------------------------
@app.post("/api/collectivites/{collectivite_id}/arbitrage:run")
def run_arbitrage(collectivite_id: str, payload: ArbitrageRunIn = Body(...)):
    db = get_db()
    try:
        data = payload.model_dump()
        data["collectivite_id"] = collectivite_id

        result = calculer_arbitrage_2_0(data)

        arbitrage_id = f"arb-{datetime.utcnow().year}-{uuid.uuid4().hex[:6]}"
        result["arbitrage_id"] = arbitrage_id
        result["collectivite_id"] = collectivite_id

        if isinstance(result.get("projets"), list):
            for p in result["projets"]:
                if isinstance(p, dict):
                    p["arbitrage_id"] = arbitrage_id

        result["created_at"] = datetime.utcnow()

        db.arbitrages.insert_one(result)

        # PyMongo peut injecter _id dans le dict
        result.pop("_id", None)

        return _json_safe(result)

    except HTTPException:
        raise
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Mongo error: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {e}")


# -----------------------------
# ARBITRAGE - FULL (dernier arbitrage + projets)
# -----------------------------
@app.get("/api/collectivites/{collectivite_id}/arbitrage:full")
def get_last_arbitrage(collectivite_id: str):
    db = get_db()

    arbitrage = db.arbitrages.find_one(
        {"collectivite_id": collectivite_id},
        sort=[("created_at", -1)],
        projection={"_id": 0},
    )

    if not arbitrage:
        raise HTTPException(status_code=404, detail="Aucun arbitrage trouvé pour cette collectivité")

    projets = list(db.projets.find({"collectivite_id": collectivite_id}, {"_id": 0}))
    arbitrage["projets"] = projets

    return _json_safe(arbitrage)


# -----------------------------
# ARBITRAGE - BY ID
# -----------------------------
@app.get("/api/collectivites/{collectivite_id}/arbitrage/{arbitrage_id}")
def get_arbitrage_by_id(collectivite_id: str, arbitrage_id: str):
    db = get_db()

    arbitrage = db.arbitrages.find_one(
        {"collectivite_id": collectivite_id, "arbitrage_id": arbitrage_id},
        projection={"_id": 0},
    )
    if not arbitrage:
        raise HTTPException(status_code=404, detail="Arbitrage introuvable")

    return _json_safe(arbitrage)


# -----------------------------
# DEBUG - created_at type
# -----------------------------
@app.get("/api/debug/last-created-at-type/{collectivite_id}")
def debug_created_at_type(collectivite_id: str):
    db = get_db()
    doc = db.arbitrages.find_one(
        {"collectivite_id": collectivite_id},
        sort=[("created_at", -1)],
        projection={"_id": 0, "created_at": 1, "arbitrage_id": 1},
    )
    if not doc:
        raise HTTPException(status_code=404, detail="No arbitrage")
    return {
        "arbitrage_id": doc.get("arbitrage_id"),
        "created_at_value": str(doc.get("created_at")),
        "python_type": str(type(doc.get("created_at"))),
    }


# -----------------------------
# DEBUG - ECHO (verif parsing JSON)
# -----------------------------
@app.post("/api/debug/echo")
def debug_echo(payload: Dict[str, Any] = Body(...)):
    return {"ok": True, "payload": payload}
PY
