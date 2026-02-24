from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Optional

from pymongo import MongoClient
import os

MONGO_URI = os.getenv("MONGO_URI", "")
mongo_client = MongoClient(MONGO_URI) if MONGO_URI else None
db = mongo_client["colconnect"] if mongo_client else None

app = FastAPI()


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
    status: str  # KEEP / DEFER / DROP
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


@app.get("/api/test-mongo")
def test_mongo():
    if not mongo_client:
        return {"status": "error", "mongo": "not_configured"}
    try:
        mongo_client.admin.command("ping")
        return {"status": "ok", "mongo": "connected"}
    except Exception:
        return {"status": "error", "mongo": "connection_failed"}


@app.get("/api/collectivites/{collectivite_id}/arbitrage:full", response_model=ArbitrageFull)
def get_arbitrage_full(collectivite_id: str):
    # Pour l’instant : exemple statique (comme ce qu’on a construit ensemble)
    return {
        "collectivite_id": "nova-sur-marne-94000",
        "arbitrage_id": "arb-2025-0001",
        "mandat": "2025-2030",
        "status": {
            "state": "done",
            "impact": "eleve",
            "urgence": "elevee",
            "horizon": "mandat"
        },
        "contraintes": {
            "budget_investissement_max": 20000000,
            "seuil_capacite_desendettement_ans": 15,
            "commentaire": "Scénario cible : maintenir la capacité de désendettement sous 15 ans à horizon 2028."
        },
        "hypotheses": {
            "taux_subventions_moyen": 0.35,
            "inflation_travaux": 0.03,
            "annee_reference": 2025
        },
        "projets": [],  # on branchera Mongo ensuite
        "synthese": {
            "nb_projets_total": 5,
            "nb_keep": 3,
            "nb_defer": 1,
            "nb_drop": 1,
            "investissement_mandat": {
                "cout_total_ttc_initial": 39000000,
                "cout_total_ttc_retenu": 29000000,
                "economies_realisees": 10000000
            },
            "impact_capacite_desendettement": {
                "capacite_initiale_2025_ans": 30,
                "capacite_proj_2028_ans": 16,
                "commentaire": "Le scénario retenu permet de réduire la trajectoire de dette mais reste proche du seuil politique fixé (15 ans)."
            },
            "commentaire_politique": "Scénario équilibré maintenant les priorités éducatives et climatiques."
        }
    }

# ---------------------------------------------------------
