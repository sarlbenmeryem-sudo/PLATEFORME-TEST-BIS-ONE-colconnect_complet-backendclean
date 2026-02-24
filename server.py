from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from pymongo import MongoClient
import os
from datetime import datetime
import uuid

# --- Mongo ---
MONGO_URI = os.getenv("MONGO_URI", "")
mongo_client = MongoClient(MONGO_URI) if MONGO_URI else None
db = mongo_client["colconnect"] if mongo_client else None

app = FastAPI()

# -----------------------------
# MODELES
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
    urgence: float
    visibilite_politique: float
    risque_financier: float
    score_global: float

class Decision(BaseModel):
    status: str
    justification: str
    decalage_annee: Optional[int] = None

class ArbitrageProjet(BaseModel):
    id: str
    nom: str
    thematique: List[str]
    ppi: PPI
    phasage: List[PhasageItem]
    plan_financement: List[PlanFinancementItem]
    scoring: Scoring
    decision: Decision

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
    projets: List[ArbitrageProjet]
    synthese: ArbitrageSynthese


# -----------------------------
# TEST MONGO
# -----------------------------
@app.get("/api/test-mongo")
def test_mongo():
    if not mongo_client:
        return {"status": "error", "mongo": "not_configured"}
    try:
        mongo_client.admin.command("ping")
        return {"status": "ok", "mongo": "connected"}
    except Exception:
        return {"status": "error", "mongo": "connection_failed"}


# -----------------------------
# IMPORT PROJETS
# -----------------------------
@app.post("/api/collectivites/{collectivite_id}/projets:import")
def import_projets(collectivite_id: str, projets: List[dict]):
    if not db:
        raise HTTPException(status_code=500, detail="MongoDB non configuré")

    db.projets.delete_many({"collectivite_id": collectivite_id})

    for p in projets:
        p["collectivite_id"] = collectivite_id
        db.projets.insert_one(p)

    return {"status": "ok", "count": len(projets)}


# -----------------------------
# GET PROJETS
# -----------------------------
@app.get("/api/collectivites/{collectivite_id}/projets")
def get_projets(collectivite_id: str):
    if not db:
        raise HTTPException(status_code=500, detail="MongoDB non configuré")

    projets = list(db.projets.find({"collectivite_id": collectivite_id}, {"_id": 0}))
    return projets


# -----------------------------
# POST ARBITRAGE RUN
# -----------------------------
@app.post("/api/collectivites/{collectivite_id}/arbitrage:run")
def run_arbitrage(collectivite_id: str, payload: dict):
    if not db:
        raise HTTPException(status_code=500, detail="MongoDB non configuré")

    arbitrage_id = f"arb-{datetime.utcnow().year}-{uuid.uuid4().hex[:6]}"

    payload["collectivite_id"] = collectivite_id
    payload["arbitrage_id"] = arbitrage_id
    payload["date_run"] = datetime.utcnow().isoformat()

    db.arbitrages.insert_one(payload)

    return {"status": "ok", "arbitrage_id": arbitrage_id}


# -----------------------------
# GET LAST ARBITRAGE
# -----------------------------
@app.get("/api/collectivites/{collectivite_id}/arbitrage:full")
def get_last_arbitrage(collectivite_id: str):
    if not db:
        raise HTTPException(status_code=500, detail="MongoDB non configuré")

    arbitrage = db.arbitrages.find_one(
        {"collectivite_id": collectivite_id},
        sort=[("date_run", -1)],
        projection={"_id": 0}
    )

    if not arbitrage:
        raise HTTPException(status_code=404, detail="Aucun arbitrage trouvé")

    return arbitrage


# -----------------------------
# GET ARBITRAGE BY ID
# -----------------------------
@app.get("/api/collectivites/{collectivite_id}/arbitrage/{arbitrage_id}")
def get_arbitrage_by_id(collectivite_id: str, arbitrage_id: str):
    if not db:
        raise HTTPException(status_code=500, detail="MongoDB non configuré")

    arbitrage = db.arbitrages.find_one(
        {"collectivite_id": collectivite_id, "arbitrage_id": arbitrage_id},
        {"_id": 0}
    )

    if not arbitrage:
        raise HTTPException(status_code=404, detail="Arbitrage introuvable")

    return arbitrage


