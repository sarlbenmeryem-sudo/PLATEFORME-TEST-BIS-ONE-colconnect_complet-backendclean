from __future__ import annotations
import os
import uuid
from datetime import datetime
from typing import List, Optional, Any, Dict

from fastapi import FastAPI, HTTPException, Body
from fastapi.encoders import jsonable_encoder
from fastapi import Body
from engine.arbitrage_v2 import calculer_arbitrage_2_0
from pydantic import BaseModel
from pymongo import MongoClient
from pymongo.errors import PyMongoError

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
# HEALTH (Render)
# -----------------------------
@app.get("/")
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
        # ping pour valider la connectivité
        mongo_client.admin.command("ping")
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"MongoDB ping failed: {e}")

    return mongo_client[DB_NAME]

# -----------------------------
# MODELS (arbitrage)
# -----------------------------
class PPI(BaseModel):
    cout_total_ttc: float
    periode_mandat: str

class PhasageItem(BaseModel):
    annee: int
    phase: str
    montant: float

class PlanFinancementItem(BaseModel):
    source: str
    montant: float

class Scoring(BaseModel):
    impact_service_public: float
    impact_transition: float
    maturite: float
    risque_financier: float
    score_global: float

class Decision(BaseModel):
    status: str  # KEEP / DEFER / DROP
    justification: str
    decalage_annee: Optional[int] = None

class ArbitrageProjet(BaseModel):
    id: str
    nom: str
    type: Optional[str] = None
    ppi: Optional[PPI] = None
    phasage: Optional[List[PhasageItem]] = None
    plan_financement: Optional[List[PlanFinancementItem]] = None
    scoring: Optional[Scoring] = None
    decision: Optional[Decision] = None

class ArbitrageSynthese(BaseModel):
    nb_projets_total: int
    nb_keep: int
    nb_defer: int
    nb_drop: int
    investissement_mandat: dict
    impact_capacite_desendettement: dict
    commentaire_politique: Optional[str] = None

class ArbitrageFull(BaseModel):
    collectivite_id: str
    arbitrage_id: str
    mandat: str
    status: dict
    contraintes: dict
    hypotheses: dict
    projets: List[dict]
    synthese: ArbitrageSynthese

# -----------------------------
# TEST MONGO
# -----------------------------
@app.get("/api/test-mongo")
def test_mongo():
    if not MONGO_URI:
        return {"status": "error", "mongo": "not_configured"}

    global mongo_client
    try:
        if mongo_client is None:
            mongo_client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        mongo_client.admin.command("ping")
        return {"status": "ok", "mongo": "connected", "db": DB_NAME}
    except PyMongoError as e:
        return {"status": "error", "mongo": "connection_failed", "detail": str(e)}

# -----------------------------
# PROJETS - IMPORT
# -----------------------------
@app.post("/api/collectivites/{collectivite_id}/projets:import")
def import_projets(collectivite_id: str, projets: List[Dict[str, Any]]):
    db = get_db()

    # Supprime les anciens projets de cette collectivité
    db.projets.delete_many({"collectivite_id": collectivite_id})

    # Insère les nouveaux
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
    return projets

# -----------------------------
# ARBITRAGE - RUN (création + stockage)
# -----------------------------
@app.post("/api/collectivites/{collectivite_id}/arbitrage:run")
def run_arbitrage(collectivite_id: str, payload: "ArbitrageRunIn"):
    try:
        db = get_db()
        payload = payload.model_dump()
        payload["collectivite_id"] = collectivite_id
        result = calculer_arbitrage_2_0(payload)

        arbitrage_id = f"arb-{datetime.utcnow().year}-{uuid.uuid4().hex[:6]}"
        result["arbitrage_id"] = arbitrage_id
        # traçabilité : tag chaque projet avec arbitrage_id
        if isinstance(result.get("projets"), list):
            for p in result["projets"]:
                if isinstance(p, dict):
                    p["arbitrage_id"] = arbitrage_id
        result["created_at"] = datetime.utcnow()

        db.arbitrages.insert_one(result)

        return _to_json_safe(result)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
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

    return arbitrage

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

    return arbitrage
from datetime import datetime

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
def debug_echo(payload: dict = Body(...)):
    return {"ok": True, "payload": payload}

# -----------------------------

# -----------------------------

# -----------------------------
from bson import ObjectId

# -----------------------------
# JSON SAFE (ObjectId etc.)
# -----------------------------
def _to_json_safe(x):
    try:
        from bson import ObjectId as _ObjectId
    except Exception:
        _ObjectId = None

    if _ObjectId is not None and isinstance(x, _ObjectId):
        return str(x)
    if isinstance(x, dict):
        return {k: _to_json_safe(v) for k, v in x.items() if k != "_id"}
    if isinstance(x, list):
        return [_to_json_safe(v) for v in x]
    return x

# -----------------------------
# Pydantic models (API contract)
# -----------------------------
from pydantic import BaseModel, Field
from typing import Literal

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
    projets: list[ProjetIn]
